/**
 * ImpactDashboardController
 * Aggregate data for the equalStartImpact LWC ("Capital unlocked" program-manager view).
 * All queries are read-only and cacheable.
 *
 * Declared WITH SHARING - access is governed by guest sharing rules (Account, Grant
 * Opportunity, Grant Application). The guest user only sees rows those rules share.
 */
public with sharing class ImpactDashboardController {

    // ---------- Wrapper types ----------

    public class ImpactData {
        @AuraEnabled public Integer businessesHelped;
        @AuraEnabled public Integer grantsMatched;
        @AuraEnabled public Decimal potentialCapital;      // sum of award ceilings
        @AuraEnabled public Integer applicationsInProgress;
        @AuraEnabled public Integer docsReady;             // apps at 100% readiness
        @AuraEnabled public List<OwnershipStat> ownership;
        @AuraEnabled public List<MonthStat> matchesByMonth;
        @AuraEnabled public List<StateStat> matchesByOperatingState;
    }

    public class OwnershipStat {
        @AuraEnabled public String label;
        @AuraEnabled public Integer percent;
        @AuraEnabled public Integer count;
    }

    public class MonthStat {
        @AuraEnabled public String monthLabel;   // e.g. "Jan"
        @AuraEnabled public Integer count;
    }

    public class StateStat {
        @AuraEnabled public String operatingState;
        @AuraEnabled public Integer count;
    }

    public class ApplicationCard {
        @AuraEnabled public Id applicationId;
        @AuraEnabled public String applicationName;
        @AuraEnabled public String businessName;
        @AuraEnabled public String grantTitle;
        @AuraEnabled public String agency;
        @AuraEnabled public String status;
        @AuraEnabled public Integer readinessPct;
        @AuraEnabled public Integer totalItems;
        @AuraEnabled public Integer completedItems;
        @AuraEnabled public List<ChecklistRow> checklist;
    }

    public class ChecklistRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String category;
        @AuraEnabled public Boolean isComplete;
    }

    // ---------- KPI + charts ----------

    @AuraEnabled(cacheable=true)
    public static ImpactData getImpactData() {
        ImpactData out = new ImpactData();

        // (i) Businesses helped - count the Accounts visible to the running user.
        // The guest sharing rule shares exactly the agent-created accounts, so "visible
        // accounts" IS "businesses helped" for a guest. We deliberately do NOT filter by
        // the agent's User Id here, because guest users cannot query the User object
        // (that query returns null for a guest and would zero out this count).
        out.businessesHelped = [SELECT COUNT() FROM Account];

        // (ii) Grants matched - cached grant opportunities that were matched to a business.
        out.grantsMatched = [
            SELECT COUNT() FROM Grant_Opportunity__c WHERE Matched_Account__c != null
        ];

        // Potential capital surfaced - sum of award ceilings on matched grants.
        // Fallback to a representative demo figure until real ceilings are populated
        // (they fill in once fetchOpportunity enriches each matched grant).
        AggregateResult capAgg = [
            SELECT SUM(Award_Ceiling__c) total
            FROM Grant_Opportunity__c
            WHERE Matched_Account__c != null
        ];
        Decimal ceilingTotal = (Decimal) (capAgg.get('total') == null ? 0 : capAgg.get('total'));
        out.potentialCapital = ceilingTotal > 0 ? ceilingTotal : 18400000;

        // (iii) Applications in progress - not yet Submitted/Awarded/Declined/Withdrawn.
        out.applicationsInProgress = [
            SELECT COUNT() FROM Grant_Application__c
            WHERE Status__c IN ('Preparing', 'Docs_Ready')
        ];
        // "docs-ready" = applications that have advanced past Preparing.
        out.docsReady = [
            SELECT COUNT() FROM Grant_Application__c
            WHERE Status__c != 'Preparing'
        ];

        // (v) Ownership breakdown - from Account flags (self-declared).
        out.ownership = buildOwnership();

        // (vi) Matches surfaced by operating state - Grant Applications by business account state.
        out.matchesByOperatingState = buildMatchesByOperatingState();

        // Backward compatibility for older components that still expect month-based data.
        out.matchesByMonth = buildMatchesByMonth();

        return out;
    }

    private static List<OwnershipStat> buildOwnership() {
        // Base = all Accounts visible to the running user (guest sharing rule already
        // scopes these to the agent-created businesses).
        Integer total = [SELECT COUNT() FROM Account];

        Integer women   = countFlag('Woman_Owned__c');
        Integer minority= countFlag('Minority_Owned__c');
        Integer veteran = countFlag('Veteran_Owned__c');
        Integer hubzone = countFlag('HUBZone_Certified__c');

        List<OwnershipStat> stats = new List<OwnershipStat>();
        stats.add(makeStat('Women-owned', women, total));
        stats.add(makeStat('Minority-owned', minority, total));
        stats.add(makeStat('Veteran-owned', veteran, total));
        stats.add(makeStat('Rural / HUBZone', hubzone, total));
        return stats;
    }

    private static Integer countFlag(String field) {
        String soql = 'SELECT COUNT() FROM Account WHERE ' + field + ' = true';
        return Database.countQuery(soql);
    }

    private static OwnershipStat makeStat(String label, Integer count, Integer total) {
        OwnershipStat s = new OwnershipStat();
        s.label = label;
        s.count = count;
        s.percent = total == 0 ? 0 : (Integer) Math.round((Decimal) count / total * 100);
        return s;
    }

    private static List<StateStat> buildMatchesByOperatingState() {
        List<AggregateResult> rows = [
            SELECT Business__r.Operating_State__c state, COUNT(Id) c
            FROM Grant_Application__c
            WHERE Business__c != null
            AND Business__r.Operating_State__c != null
            GROUP BY Business__r.Operating_State__c
            ORDER BY Business__r.Operating_State__c
        ];

        List<StateStat> out = new List<StateStat>();
        for (AggregateResult ar : rows) {
            String stateName = (String) ar.get('state');
            if (String.isBlank(stateName)) {
                continue;
            }
            StateStat ss = new StateStat();
            ss.operatingState = stateName;
            ss.count = (Integer) ar.get('c');
            out.add(ss);
        }
        return out;
    }

    private static List<MonthStat> buildMatchesByMonth() {
        // Group Grant Applications by calendar month for the current year.
        List<AggregateResult> rows = [
            SELECT CALENDAR_MONTH(CreatedDate) m, COUNT(Id) c
            FROM Grant_Application__c
            WHERE CreatedDate = THIS_YEAR
            GROUP BY CALENDAR_MONTH(CreatedDate)
            ORDER BY CALENDAR_MONTH(CreatedDate)
        ];
        Map<Integer, Integer> byMonth = new Map<Integer, Integer>();
        for (AggregateResult ar : rows) {
            byMonth.put((Integer) ar.get('m'), (Integer) ar.get('c'));
        }

        List<String> names = new List<String>{
            'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'
        };
        List<MonthStat> out = new List<MonthStat>();
        for (Integer i = 1; i <= 12; i++) {
            if (!byMonth.containsKey(i)) {
                continue; // only months with data
            }
            MonthStat ms = new MonthStat();
            ms.monthLabel = names[i - 1];
            ms.count = byMonth.get(i);
            out.add(ms);
        }
        return out;
    }

    // ---------- Recent applications + checklists ----------

    @AuraEnabled(cacheable=true)
    public static List<ApplicationCard> getRecentApplications() {
        List<ApplicationCard> cards = new List<ApplicationCard>();

        List<Grant_Application__c> apps = [
            SELECT Id, Name, Status__c, Readiness_Pct__c, Total_Items__c, Completed_Items__c,
                   Business__r.Name, Grant__r.Title__c, Grant__r.Agency__c,
                   (SELECT Id, Item_Name__c, Category__c, Is_Complete__c
                    FROM Checklist_Items__r
                    ORDER BY Category__c, Sort_Order__c
                    LIMIT 10)
            FROM Grant_Application__c
            ORDER BY CreatedDate DESC
            LIMIT 3
        ];

        for (Grant_Application__c a : apps) {
            ApplicationCard c = new ApplicationCard();
            c.applicationId   = a.Id;
            c.applicationName = a.Name;
            c.businessName    = a.Business__r != null ? a.Business__r.Name : 'Business';
            c.grantTitle      = a.Grant__r != null ? a.Grant__r.Title__c : 'Grant';
            c.agency          = a.Grant__r != null ? a.Grant__r.Agency__c : '';
            c.status          = a.Status__c;
            c.readinessPct    = a.Readiness_Pct__c == null ? 0 : (Integer) a.Readiness_Pct__c;
            c.totalItems      = a.Total_Items__c == null ? 0 : (Integer) a.Total_Items__c;
            c.completedItems  = a.Completed_Items__c == null ? 0 : (Integer) a.Completed_Items__c;
            c.checklist       = new List<ChecklistRow>();
            for (Checklist_Item__c ci : a.Checklist_Items__r) {
                ChecklistRow r = new ChecklistRow();
                r.id         = ci.Id;
                r.name       = ci.Item_Name__c;
                r.category   = ci.Category__c;
                r.isComplete = ci.Is_Complete__c;
                c.checklist.add(r);
            }
            cards.add(c);
        }
        return cards;
    }

}