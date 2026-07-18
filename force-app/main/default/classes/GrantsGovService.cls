/**
 * GrantsGovService
 * Invocable Apex for Agentforce actions against the public Grants.gov API.
 * Endpoints: search2, fetchOpportunity (both POST JSON, no auth).
 * Resilience: mock-mode switch, timeout handling, non-200 fallback, cache-backed degradation.
 */
public with sharing class GrantsGovService {

    @TestVisible private static final Integer DEFAULT_TIMEOUT_MS = 20000;
    @TestVisible private static final Integer DEFAULT_ROWS       = 10;
    @TestVisible private static final String  SEARCH_PATH        = '/v1/api/search2';
    @TestVisible private static final String  FETCH_PATH         = '/v1/api/fetchOpportunity';

    // ========== Invocable Request/Response DTOs ==========

    public class SearchRequest {
        // Declared as String (not Id) so the reflected Agent Script action input is a
        // plain string, avoiding the lightning__recordIdType complex-type requirement.
        // Apex coerces the string in the SOQL bind inside loadAccount().
        @InvocableVariable(label='Account Id' required=true)
        public String accountId;

        @InvocableVariable(label='Keyword Override')
        public String keywordOverride;

        @InvocableVariable(label='Max Rows')
        public Integer maxRows;
    }

    public class SearchResult {
        @InvocableVariable public String summaryForAgent;
        @InvocableVariable public List<Id> grantRecordIds;
        @InvocableVariable public Boolean liveData;
        @InvocableVariable public Integer hitCount;
        @InvocableVariable public String degradationReason;
    }

    public class FetchRequest {
        @InvocableVariable(label='Opportunity Id' required=true)
        public String opportunityId;
    }

    public class FetchResult {
        @InvocableVariable public Id grantRecordId;
        @InvocableVariable public String eligibilitySummary;
        @InvocableVariable public Decimal awardCeiling;
        @InvocableVariable public Boolean liveData;
    }

    // ========== Public API (called by SearchGrantsAction / FetchGrantDetailAction) ==========

    public static List<SearchResult> searchGrants(List<SearchRequest> reqs) {
        List<SearchResult> results = new List<SearchResult>();
        EqualStart_Config__c cfg = EqualStart_Config__c.getInstance();
        for (SearchRequest req : reqs) {
            results.add(runSearch(req, cfg));
        }
        return results;
    }

    public static List<FetchResult> fetchOpportunity(List<FetchRequest> reqs) {
        List<FetchResult> results = new List<FetchResult>();
        EqualStart_Config__c cfg = EqualStart_Config__c.getInstance();
        for (FetchRequest req : reqs) {
            results.add(runFetch(req, cfg));
        }
        return results;
    }

    // ========== Core: search ==========

    @TestVisible
    private static SearchResult runSearch(SearchRequest req, EqualStart_Config__c cfg) {
        SearchResult r = new SearchResult();
        r.grantRecordIds = new List<Id>();

        Account biz = loadAccount(req.accountId);
        if (biz == null) {
            r.summaryForAgent = 'I could not find your business profile. Let\'s complete it first.';
            r.liveData = false;
            r.degradationReason = 'ACCOUNT_NOT_FOUND';
            return r;
        }

        if (cfg != null && cfg.Use_Mock_Data__c == true) {
            return buildMockSearch(biz, 'MOCK_MODE_ENABLED');
        }

        // Safety net: refuse to run an unfiltered search. Without a real industry keyword
        // the API returns a large, irrelevant grab-bag, so ask for the business industry
        // instead of searching on "use of funds" (or nothing) alone.
        String keyword = resolveKeyword(biz, req);
        if (String.isBlank(keyword)) {
            r.summaryForAgent = 'To find relevant grants I need to know what your business does '
                + '(your industry or line of work, e.g. "solar installation"). Please tell me your '
                + 'business type or industry - not what you would spend the money on.';
            r.liveData = false;
            r.hitCount = 0;
            r.degradationReason = 'NO_INDUSTRY_KEYWORD';
            return r;
        }

        String body = buildSearchBody(biz, req);
        HttpResponse resp = null;
        try {
            resp = doCallout(SEARCH_PATH, body, timeoutMs(cfg));
        } catch (System.CalloutException ce) {
            return degradeToCache(biz, 'CALLOUT_EXCEPTION: ' + ce.getMessage());
        } catch (Exception e) {
            return degradeToCache(biz, 'UNEXPECTED: ' + e.getMessage());
        }

        if (resp == null || resp.getStatusCode() != 200) {
            return degradeToCache(biz,
                'HTTP_' + (resp == null ? 'NULL' : String.valueOf(resp.getStatusCode())));
        }

        try {
            List<Grant_Opportunity__c> upserts = parseSearchResponse(resp.getBody(), biz);

            if (!upserts.isEmpty()) {
                Schema.SObjectField extId = Grant_Opportunity__c.Fields.Opportunity_Number__c;
                Database.upsert(upserts, extId, false);
                for (Grant_Opportunity__c g : upserts) {
                    if (g.Id != null) r.grantRecordIds.add(g.Id);
                }
            }

            r.liveData = true;
            r.hitCount = upserts.size();
            r.summaryForAgent = renderSummary(upserts);
        } catch (Exception parseEx) {
            return degradeToCache(biz, 'PARSE_ERROR: ' + parseEx.getMessage());
        }
        return r;
    }

    /**
     * Parses the search2 response using deserializeUntyped so we can safely read the
     * `number` field (reserved word in Apex classes).
     */
    @TestVisible
    private static List<Grant_Opportunity__c> parseSearchResponse(String rawJson, Account biz) {
        List<Grant_Opportunity__c> out = new List<Grant_Opportunity__c>();
        if (String.isBlank(rawJson)) return out;

        Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(rawJson);
        Map<String, Object> data = (Map<String, Object>) root.get('data');
        if (data == null) return out;

        List<Object> hits = (List<Object>) data.get('oppHits');
        if (hits == null) return out;

        Datetime now = Datetime.now();
        for (Object h : hits) {
            Map<String, Object> hit = (Map<String, Object>) h;
            String oppNumber = safeString(hit.get('number'));
            if (String.isBlank(oppNumber)) continue;

            // Live search2 uses 'agency' (the display name) and 'agencyCode'.
            // 'agencyName' does not exist on the hit, so fall back across both.
            String agencyName = safeString(hit.get('agency'));
            if (String.isBlank(agencyName)) agencyName = safeString(hit.get('agencyName'));

            Grant_Opportunity__c g = new Grant_Opportunity__c(
                Opportunity_Number__c = oppNumber,
                Opportunity_ID__c     = safeString(hit.get('id')),
                Title__c              = truncate(safeString(hit.get('title')), 255),
                Agency__c             = truncate(agencyName, 120),
                Agency_Code__c        = truncate(safeString(hit.get('agencyCode')), 40),
                Open_Date__c          = parseDate(safeString(hit.get('openDate'))),
                Close_Date__c         = parseDate(safeString(hit.get('closeDate'))),
                Status__c             = safeString(hit.get('oppStatus')),
                Last_Refreshed__c     = now,
                Matched_Account__c    = biz.Id,
                Match_Rationale__c    = deriveRationale(biz),
                Raw_Payload__c        = JSON.serialize(hit)
            );
            out.add(g);
        }
        return out;
    }

    // ========== Core: fetch ==========

    @TestVisible
    private static FetchResult runFetch(FetchRequest req, EqualStart_Config__c cfg) {
        FetchResult f = new FetchResult();

        if (cfg != null && cfg.Use_Mock_Data__c == true) {
            f.liveData = false;
            f.eligibilitySummary =
                'Mock detail: veteran-owned set-aside; small business under 50 employees; ' +
                'NAICS 238220 in scope; requires SAM.gov active registration.';
            f.awardCeiling = 100000;
            return f;
        }

        String body = JSON.serialize(new Map<String, Object>{ 'opportunityId' => req.opportunityId });
        HttpResponse resp;
        try {
            resp = doCallout(FETCH_PATH, body, timeoutMs(cfg));
        } catch (Exception e) {
            f.liveData = false;
            return f;
        }
        if (resp == null || resp.getStatusCode() != 200) {
            f.liveData = false;
            return f;
        }

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(resp.getBody());
        Map<String, Object> data   = (Map<String, Object>) parsed.get('data');
        if (data == null) { f.liveData = false; return f; }

        // Live fetchOpportunity nests the detail in a 'synopsis' object; award ceiling
        // and the description text live there, not at the top level.
        Map<String, Object> syn = (data.get('synopsis') instanceof Map<String, Object>)
            ? (Map<String, Object>) data.get('synopsis')
            : new Map<String, Object>();

        String eligibilityText = safeString(syn.get('applicantEligibilityDesc'));
        if (String.isBlank(eligibilityText)) eligibilityText = safeString(syn.get('synopsisDesc'));
        String synopsis = stripHtml(eligibilityText);
        Decimal ceiling = parseDecimal(syn.get('awardCeiling'));

        List<Grant_Opportunity__c> matches = [
            SELECT Id FROM Grant_Opportunity__c
            WHERE Opportunity_ID__c = :req.opportunityId LIMIT 1
        ];
        if (!matches.isEmpty()) {
            matches[0].Eligibility_Summary__c = truncate(synopsis, 32000);
            matches[0].Award_Ceiling__c       = ceiling;
            matches[0].Last_Refreshed__c      = Datetime.now();
            update matches[0];
            f.grantRecordId = matches[0].Id;
        }

        f.eligibilitySummary = truncate(synopsis, 4000);
        f.awardCeiling       = ceiling;
        f.liveData           = true;
        return f;
    }

    // ========== Helpers ==========

    @TestVisible
    private static Integer timeoutMs(EqualStart_Config__c cfg) {
        if (cfg != null && cfg.Callout_Timeout_Ms__c != null) {
            return Integer.valueOf(cfg.Callout_Timeout_Ms__c);
        }
        return DEFAULT_TIMEOUT_MS;
    }

    @TestVisible
    private static HttpResponse doCallout(String path, String body, Integer timeout) {
        HttpRequest hr = new HttpRequest();
        hr.setEndpoint('callout:Grants_gov_API' + path);
        hr.setMethod('POST');
        hr.setHeader('Content-Type', 'application/json');
        hr.setHeader('Accept', 'application/json');
        hr.setTimeout(timeout);
        hr.setBody(body);
        return new Http().send(hr);
    }

    /**
     * Resolves the search keyword with a strict precedence so we never search on
     * "use of funds" text alone:
     *   1) keywordOverride  - explicit business industry passed by the agent action
     *   2) Account.Industry - dedicated industry field on the profile
     *   3) Industry_Keywords__c - legacy free-text field (last resort; historically was
     *      sometimes polluted with "use of funds", which yields irrelevant matches)
     */
    @TestVisible
    private static String resolveKeyword(Account biz, SearchRequest req) {
        if (req != null && String.isNotBlank(req.keywordOverride)) {
            return req.keywordOverride.trim();
        }
        if (biz != null && String.isNotBlank(biz.Industry)) {
            return biz.Industry.trim();
        }
        if (biz != null && String.isNotBlank(biz.Industry_Keywords__c)) {
            return biz.Industry_Keywords__c.trim();
        }
        return '';
    }

    @TestVisible
    private static String buildSearchBody(Account biz, SearchRequest req) {
        String keyword = resolveKeyword(biz, req);
        String fundingCat = mapNaicsToCategory(biz.NAICS_Code__c);
        Integer rows = (req != null && req.maxRows != null && req.maxRows > 0)
            ? req.maxRows : DEFAULT_ROWS;

        Map<String, Object> payload = new Map<String, Object>{
            'keyword'           => keyword,
            'oppStatuses'       => 'posted|forecasted',
            'fundingCategories' => fundingCat,
            'rows'              => rows,
            'startRecordNum'    => 0
        };
        return JSON.serialize(payload);
    }

    @TestVisible
    private static String mapNaicsToCategory(String naics) {
        if (String.isBlank(naics)) return '';
        List<Grant_Category_Mapping__mdt> maps = [
            SELECT NAICS_Prefix__c, Funding_Category_Code__c, Priority__c
            FROM Grant_Category_Mapping__mdt
            WHERE Active__c = true
            ORDER BY Priority__c ASC
        ];
        for (Grant_Category_Mapping__mdt m : maps) {
            if (String.isNotBlank(m.NAICS_Prefix__c) && naics.startsWith(m.NAICS_Prefix__c)) {
                return m.Funding_Category_Code__c;
            }
        }
        return '';
    }

    @TestVisible
    private static String deriveRationale(Account biz) {
        List<String> reasons = new List<String>();
        if (biz.Veteran_Owned__c == true)  reasons.add('veteran-owned eligibility asserted');
        if (biz.Woman_Owned__c == true)    reasons.add('woman-owned priority pathway');
        if (biz.Minority_Owned__c == true) reasons.add('minority-owned set-aside pathway');
        if (String.isNotBlank(biz.Operating_State__c)) {
            reasons.add('operating in ' + biz.Operating_State__c);
        }
        if (String.isNotBlank(biz.NAICS_Code__c)) {
            reasons.add('NAICS ' + biz.NAICS_Code__c + ' in scope');
        }
        return String.join(reasons, ' | ');
    }

    @TestVisible
    private static SearchResult degradeToCache(Account biz, String reason) {
        SearchResult r = new SearchResult();
        r.liveData = false;
        r.degradationReason = reason;

        List<Grant_Opportunity__c> cached = [
            SELECT Id, Opportunity_Number__c, Title__c, Agency__c,
                   Award_Ceiling__c, Close_Date__c
            FROM Grant_Opportunity__c
            WHERE Matched_Account__c = :biz.Id
            ORDER BY Last_Refreshed__c DESC NULLS LAST
            LIMIT 5
        ];
        r.grantRecordIds = new List<Id>();
        for (Grant_Opportunity__c g : cached) r.grantRecordIds.add(g.Id);
        r.hitCount = cached.size();
        r.summaryForAgent = 'Live service unavailable - showing cached matches. ' + renderSummary(cached);
        return r;
    }

    @TestVisible
    private static SearchResult buildMockSearch(Account biz, String reason) {
        SearchResult r = new SearchResult();
        r.liveData = false;
        r.degradationReason = reason;
        r.hitCount = 2;
        r.grantRecordIds = new List<Id>();
        r.summaryForAgent =
            'MOCK: (1) VETBIZ-26-011 - Veteran-Owned Small Business Innovation Fund - SBA - ' +
            'ceiling $100,000 - closes Aug 14. (2) EERE-26-2044 - Ohio Clean Energy Small ' +
            'Business Deployment Grant - DOE - ceiling $50,000 - closes Jul 29.';
        return r;
    }

    @TestVisible
    private static String renderSummary(List<Grant_Opportunity__c> gs) {
        if (gs == null || gs.isEmpty()) {
            return 'No opportunities were found. I can widen the search or you can update your industry keywords.';
        }
        List<String> lines = new List<String>();
        Integer i = 1;
        for (Grant_Opportunity__c g : gs) {
            String num      = g.Opportunity_Number__c != null ? g.Opportunity_Number__c : '';
            String title    = g.Title__c != null ? g.Title__c : num;
            String agency   = g.Agency__c != null ? g.Agency__c : 'Federal agency';
            String ceiling  = g.Award_Ceiling__c != null ? '$' + g.Award_Ceiling__c.format() : 'TBD';
            String closesOn = g.Close_Date__c != null ? String.valueOf(g.Close_Date__c) : 'TBD';
            // Include the opportunity number as the selection key the agent captures.
            lines.add('(' + i + ') [' + num + '] ' + title + ' - ' + agency
                + ' - ceiling ' + ceiling + ' - closes ' + closesOn);
            i++;
        }
        return String.join(lines, '\n');
    }

    @TestVisible
    private static Account loadAccount(String accId) {
        if (String.isBlank(accId)) return null;
        List<Account> rs = [
            SELECT Id, Name, Industry, NAICS_Code__c, Industry_Keywords__c, Operating_State__c,
                   Minority_Owned__c, Woman_Owned__c, Veteran_Owned__c
            FROM Account WHERE Id = :accId LIMIT 1
        ];
        return rs.isEmpty() ? null : rs[0];
    }

    @TestVisible
    private static String safeString(Object o) {
        return (o == null) ? null : String.valueOf(o);
    }
    /**
     * Grants.gov returns dates as MM/DD/YYYY (e.g. "10/13/2015"), and sometimes an
     * empty string. Parse that format; also tolerate ISO YYYY-MM-DD just in case.
     */
    @TestVisible
    private static Date parseDate(String s) {
        if (String.isBlank(s)) return null;
        // MM/DD/YYYY
        if (s.contains('/')) {
            List<String> parts = s.split('/');
            if (parts.size() == 3) {
                try {
                    return Date.newInstance(
                        Integer.valueOf(parts[2]),   // year
                        Integer.valueOf(parts[0]),   // month
                        Integer.valueOf(parts[1]));  // day
                } catch (Exception e) { return null; }
            }
            return null;
        }
        // ISO fallback (YYYY-MM-DD)
        try { return Date.valueOf(s); } catch (Exception e) { return null; }
    }
    @TestVisible
    private static Decimal parseDecimal(Object o) {
        if (o == null) return null;
        try { return Decimal.valueOf(String.valueOf(o)); } catch (Exception e) { return null; }
    }
    @TestVisible
    private static String truncate(String s, Integer n) {
        return (s == null) ? null : (s.length() > n ? s.substring(0, n) : s);
    }
    /**
     * Synopsis/eligibility text can contain HTML markup and CR/LF noise. Strip tags and
     * collapse whitespace so the stored text and any prompt grounding stays clean.
     */
    @TestVisible
    private static String stripHtml(String s) {
        if (String.isBlank(s)) return s;
        String noTags = s.replaceAll('<[^>]+>', ' ');
        return noTags.replaceAll('\\s+', ' ').trim();
    }
}