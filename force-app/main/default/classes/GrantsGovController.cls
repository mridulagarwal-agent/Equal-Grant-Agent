/**
 * GrantsGovController
 * @AuraEnabled facade for the grantResultsPanel LWC.
 */
public with sharing class GrantsGovController {

    public class MatchedResult {
        @AuraEnabled public List<GrantDisplay> grants;
        @AuraEnabled public Boolean liveData;
    }

    public class GrantDisplay {
        @AuraEnabled public Id id;
        @AuraEnabled public String opportunityNumber;
        @AuraEnabled public String title;
        @AuraEnabled public String agency;
        @AuraEnabled public String awardCeilingFormatted;
        @AuraEnabled public String closeDateFormatted;
        @AuraEnabled public Integer daysToClose;
        @AuraEnabled public String matchRationale;
    }

    /**
     * Returns the most-recently refreshed matched grants for the given account.
     * This is a cache reader - it does not trigger a fresh callout.
     * The Agentforce action GrantsGovService.searchGrants is what refreshes the cache.
     */
    @AuraEnabled(cacheable=true)
    public static MatchedResult getMatchedGrants(Id accountId) {
        MatchedResult out = new MatchedResult();
        out.grants = new List<GrantDisplay>();
        out.liveData = true;

        List<Grant_Opportunity__c> rows;
        if (accountId != null) {
            // Authenticated: show this business's matched grants.
            rows = [
                SELECT Id, Opportunity_Number__c, Title__c, Agency__c,
                       Award_Ceiling__c, Close_Date__c, Match_Rationale__c
                FROM Grant_Opportunity__c
                WHERE Matched_Account__c = :accountId
                ORDER BY Last_Refreshed__c DESC NULLS LAST
                LIMIT 25
            ];
        } else {
            // Guest/demo fallback: no account context, so show the most recently
            // cached opportunities (whatever the agent's last search surfaced).
            rows = [
                SELECT Id, Opportunity_Number__c, Title__c, Agency__c,
                       Award_Ceiling__c, Close_Date__c, Match_Rationale__c
                FROM Grant_Opportunity__c
                WHERE Last_Refreshed__c != null
                ORDER BY Last_Refreshed__c DESC NULLS LAST
                LIMIT 6
            ];
        }

        Date today = Date.today();
        for (Grant_Opportunity__c g : rows) {
            GrantDisplay d = new GrantDisplay();
            d.id                    = g.Id;
            d.opportunityNumber     = g.Opportunity_Number__c;
            d.title                 = g.Title__c;
            d.agency                = g.Agency__c;
            d.awardCeilingFormatted = g.Award_Ceiling__c == null
                ? 'TBD'
                : '$' + g.Award_Ceiling__c.setScale(0).format();
            d.closeDateFormatted    = g.Close_Date__c == null
                ? 'TBD'
                : g.Close_Date__c.format();
            d.daysToClose = g.Close_Date__c == null
                ? null
                : today.daysBetween(g.Close_Date__c);
            d.matchRationale        = g.Match_Rationale__c;
            out.grants.add(d);
        }
        return out;
    }
}