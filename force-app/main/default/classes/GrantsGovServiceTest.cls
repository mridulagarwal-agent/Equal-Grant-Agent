@IsTest
private class GrantsGovServiceTest {

    // ========== Http mocks ==========

    private class HappyPathMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse r = new HttpResponse();
            r.setStatusCode(200);
            r.setHeader('Content-Type', 'application/json');
            if (req.getEndpoint().endsWith('/v1/api/search2')) {
                // Mirrors the LIVE search2 shape: 'agency' (not agencyName), MM/DD/YYYY
                // dates, and a possibly-empty closeDate.
                r.setBody(
                    '{"errorcode":0,"data":{"hitCount":2,"oppHits":[' +
                    '{"id":"111","number":"VETBIZ-26-011","title":"Veteran-Owned Small Business Innovation Fund",' +
                    '"agency":"Small Business Administration","agencyCode":"SBA","openDate":"06/01/2026","closeDate":"08/14/2026","oppStatus":"posted"},' +
                    '{"id":"222","number":"EERE-26-2044","title":"Ohio Clean Energy Small Business Deployment Grant",' +
                    '"agency":"Department of Energy","agencyCode":"DOE","openDate":"05/01/2026","closeDate":"","oppStatus":"posted"}' +
                    ']}}'
                );
            } else {
                // Mirrors the LIVE fetchOpportunity shape: detail nested in synopsis object,
                // award ceiling as a string, description with HTML noise.
                r.setBody(
                    '{"errorcode":0,"data":{"id":111,"opportunityNumber":"VETBIZ-26-011","synopsis":{' +
                    '"awardCeiling":"100000","awardFloor":"25000",' +
                    '"applicantEligibilityDesc":"<p>Veteran set-aside.</p>\\r\\n Requires active SAM.gov registration.",' +
                    '"synopsisDesc":"Fund for veteran-owned small businesses."}}}'
                );
            }
            return r;
        }
    }

    private class TimeoutMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            CalloutException ce = new CalloutException();
            ce.setMessage('Read timed out');
            throw ce;
        }
    }

    private class Http500Mock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse r = new HttpResponse();
            r.setStatusCode(500);
            r.setBody('{"error":"boom"}');
            return r;
        }
    }

    private class EmptyMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse r = new HttpResponse();
            r.setStatusCode(200);
            r.setBody('{"data":{"hitCount":0,"oppHits":[]}}');
            return r;
        }
    }

    // ========== Test data ==========

    private static Account makeAccount() {
        Account a = new Account(
            Name                  = 'Whitfield Solar LLC',
            NAICS_Code__c         = '238220',
            Industry_Keywords__c  = 'solar installation',
            Operating_State__c    = 'OH',
            Veteran_Owned__c      = true,
            Woman_Owned__c        = true,
            Business_Stage__c     = 'Growth',
            Revenue_Band__c       = '100k_1M'
        );
        insert a;
        return a;
    }

    // ========== search: happy path ==========

    @IsTest
    static void search_happyPath_upsertsAndReturnsLive() {
        Account biz = makeAccount();
        Test.setMock(HttpCalloutMock.class, new HappyPathMock());

        GrantsGovService.SearchRequest req = new GrantsGovService.SearchRequest();
        req.accountId = biz.Id;

        Test.startTest();
        List<GrantsGovService.SearchResult> res = GrantsGovService.searchGrants(
            new List<GrantsGovService.SearchRequest>{ req });
        Test.stopTest();

        System.assertEquals(1, res.size(), 'one result per request');
        System.assertEquals(true, res[0].liveData, 'should be marked live');
        System.assertEquals(2, res[0].hitCount);
        System.assert(res[0].summaryForAgent.contains('Veteran-Owned'),
            'summary should list the veteran fund');

        List<Grant_Opportunity__c> upserted = [
            SELECT Id, Opportunity_Number__c, Agency__c, Open_Date__c, Close_Date__c, Match_Rationale__c
            FROM Grant_Opportunity__c
            WHERE Matched_Account__c = :biz.Id
            ORDER BY Opportunity_Number__c
        ];
        System.assertEquals(2, upserted.size());
        // Agency parsed from the live 'agency' field (not agencyName).
        System.assertEquals('Department of Energy', upserted[0].Agency__c);
        // MM/DD/YYYY dates parsed correctly; empty closeDate left null.
        System.assertEquals(Date.newInstance(2026, 5, 1), upserted[0].Open_Date__c);
        System.assertEquals(null, upserted[0].Close_Date__c, 'empty closeDate should be null');
        System.assertEquals(Date.newInstance(2026, 8, 14), upserted[1].Close_Date__c);
        System.assert(upserted[1].Match_Rationale__c.contains('veteran'));
    }

    // ========== search: timeout ==========

    @IsTest
    static void search_timeout_degradesToCache() {
        Account biz = makeAccount();

        // Pre-seed a cached grant so cache-fallback has something to show
        insert new Grant_Opportunity__c(
            Opportunity_Number__c = 'CACHED-1',
            Title__c              = 'Cached Grant',
            Agency__c             = 'SBA',
            Matched_Account__c    = biz.Id,
            Last_Refreshed__c     = Datetime.now().addDays(-1)
        );

        Test.setMock(HttpCalloutMock.class, new TimeoutMock());
        GrantsGovService.SearchRequest req = new GrantsGovService.SearchRequest();
        req.accountId = biz.Id;

        Test.startTest();
        List<GrantsGovService.SearchResult> res = GrantsGovService.searchGrants(
            new List<GrantsGovService.SearchRequest>{ req });
        Test.stopTest();

        System.assertEquals(false, res[0].liveData);
        System.assert(res[0].degradationReason.startsWith('CALLOUT_EXCEPTION'));
        System.assert(res[0].summaryForAgent.startsWith('Live service unavailable'));
        System.assertEquals(1, res[0].hitCount);
    }

    // ========== search: HTTP 500 ==========

    @IsTest
    static void search_500_degradesToCache() {
        Account biz = makeAccount();
        Test.setMock(HttpCalloutMock.class, new Http500Mock());

        GrantsGovService.SearchRequest req = new GrantsGovService.SearchRequest();
        req.accountId = biz.Id;

        Test.startTest();
        List<GrantsGovService.SearchResult> res = GrantsGovService.searchGrants(
            new List<GrantsGovService.SearchRequest>{ req });
        Test.stopTest();

        System.assertEquals(false, res[0].liveData);
        System.assertEquals('HTTP_500', res[0].degradationReason);
    }

    // ========== search: empty response ==========

    @IsTest
    static void search_empty_returnsZeroHits() {
        Account biz = makeAccount();
        Test.setMock(HttpCalloutMock.class, new EmptyMock());

        GrantsGovService.SearchRequest req = new GrantsGovService.SearchRequest();
        req.accountId = biz.Id;

        Test.startTest();
        List<GrantsGovService.SearchResult> res = GrantsGovService.searchGrants(
            new List<GrantsGovService.SearchRequest>{ req });
        Test.stopTest();

        System.assertEquals(true, res[0].liveData);
        System.assertEquals(0, res[0].hitCount);
        System.assert(res[0].summaryForAgent.contains('No opportunities'));
    }

    // ========== search: mock-mode toggle ==========

    @IsTest
    static void search_mockMode_skipsCallout() {
        Account biz = makeAccount();

        EqualStart_Config__c cfg = new EqualStart_Config__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Use_Mock_Data__c = true
        );
        insert cfg;

        GrantsGovService.SearchRequest req = new GrantsGovService.SearchRequest();
        req.accountId = biz.Id;

        Test.startTest();
        List<GrantsGovService.SearchResult> res = GrantsGovService.searchGrants(
            new List<GrantsGovService.SearchRequest>{ req });
        Test.stopTest();

        System.assertEquals('MOCK_MODE_ENABLED', res[0].degradationReason);
        System.assert(res[0].summaryForAgent.startsWith('MOCK:'));
    }

    // ========== search: missing account ==========

    @IsTest
    static void search_missingAccount_returnsFriendlyMessage() {
        GrantsGovService.SearchRequest req = new GrantsGovService.SearchRequest();
        req.accountId = null;

        Test.startTest();
        List<GrantsGovService.SearchResult> res = GrantsGovService.searchGrants(
            new List<GrantsGovService.SearchRequest>{ req });
        Test.stopTest();

        System.assertEquals(false, res[0].liveData);
        System.assertEquals('ACCOUNT_NOT_FOUND', res[0].degradationReason);
    }

    // ========== fetch: happy path ==========

    @IsTest
    static void fetch_happyPath_enrichesCache() {
        Account biz = makeAccount();
        Grant_Opportunity__c g = new Grant_Opportunity__c(
            Opportunity_Number__c = 'VETBIZ-26-011',
            Opportunity_ID__c     = '111',
            Title__c              = 'Veteran Fund',
            Matched_Account__c    = biz.Id
        );
        insert g;

        Test.setMock(HttpCalloutMock.class, new HappyPathMock());
        GrantsGovService.FetchRequest req = new GrantsGovService.FetchRequest();
        req.opportunityId = '111';

        Test.startTest();
        List<GrantsGovService.FetchResult> res = GrantsGovService.fetchOpportunity(
            new List<GrantsGovService.FetchRequest>{ req });
        Test.stopTest();

        System.assertEquals(true, res[0].liveData);
        System.assertEquals(100000, res[0].awardCeiling);
        Grant_Opportunity__c refreshed = [
            SELECT Award_Ceiling__c, Eligibility_Summary__c
            FROM Grant_Opportunity__c WHERE Id = :g.Id
        ];
        System.assertEquals(100000, refreshed.Award_Ceiling__c);
        System.assert(refreshed.Eligibility_Summary__c.contains('SAM.gov'));
    }

    // ========== fetch: mock-mode ==========

    @IsTest
    static void fetch_mockMode_returnsCannedSummary() {
        EqualStart_Config__c cfg = new EqualStart_Config__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Use_Mock_Data__c = true
        );
        insert cfg;

        GrantsGovService.FetchRequest req = new GrantsGovService.FetchRequest();
        req.opportunityId = '111';

        Test.startTest();
        List<GrantsGovService.FetchResult> res = GrantsGovService.fetchOpportunity(
            new List<GrantsGovService.FetchRequest>{ req });
        Test.stopTest();

        System.assertEquals(false, res[0].liveData);
        System.assertEquals(100000, res[0].awardCeiling);
        System.assert(res[0].eligibilitySummary.startsWith('Mock detail'));
    }

    // ========== fetch: 500 -> liveData false, no exception ==========

    @IsTest
    static void fetch_500_returnsNotLive() {
        Test.setMock(HttpCalloutMock.class, new Http500Mock());
        GrantsGovService.FetchRequest req = new GrantsGovService.FetchRequest();
        req.opportunityId = '999';

        Test.startTest();
        List<GrantsGovService.FetchResult> res = GrantsGovService.fetchOpportunity(
            new List<GrantsGovService.FetchRequest>{ req });
        Test.stopTest();

        System.assertEquals(false, res[0].liveData);
    }
}