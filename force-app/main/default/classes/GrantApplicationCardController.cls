/**
 * GrantApplicationCardController
 * Read-only data provider for the grantApplicationCard LWC placed on the
 * Grant Application record page. Returns, in one shape, the application's
 * headline + readiness, the connected business (Account) profile, the linked
 * grant opportunity detail, and the document checklist grouped by category.
 *
 * This is the internal (relationship-manager) view: when a caller quotes their
 * application or case number, the RM opens the record and sees everything here.
 */
public with sharing class GrantApplicationCardController {

    @AuraEnabled(cacheable=true)
    public static CardData getCard(Id applicationId) {
        CardData card = new CardData();
        if (applicationId == null) {
            return card;
        }

        List<Grant_Application__c> apps = [
            SELECT Id, Name, Status__c, Readiness_Pct__c, Total_Items__c, Completed_Items__c,
                   Target_Deadline__c, Executive_Summary_Draft__c,
                   Escalation_Required__c, Escalated_Case__c, Escalated_Case__r.CaseNumber,
                   Business__c, Business__r.Name, Business__r.Operating_State__c,
                   Business__r.NumberOfEmployees, Business__r.Revenue_Band__c,
                   Business__r.NAICS_Code__c, Business__r.Industry_Keywords__c,
                   Business__r.Minority_Owned__c, Business__r.Woman_Owned__c,
                   Business__r.Veteran_Owned__c, Business__r.HUBZone_Certified__c,
                   Business__r.SAM_Registration_Active__c, Business__r.SAM_UEI__c,
                   Grant__c, Grant__r.Title__c, Grant__r.Agency__c, Grant__r.Opportunity_Number__c,
                   Grant__r.Funding_Category__c, Grant__r.Close_Date__c, Grant__r.Award_Ceiling__c,
                   Grant__r.Eligibility_Summary__c, Grant__r.Match_Rationale__c, Grant__r.Source_URL__c,
                   (SELECT Item_Name__c, Category__c, Is_Complete__c, Guidance__c
                    FROM Checklist_Items__r
                    ORDER BY Category__c, Sort_Order__c
                    LIMIT 50)
            FROM Grant_Application__c
            WHERE Id = :applicationId
            LIMIT 1
        ];
        if (apps.isEmpty()) {
            return card;
        }
        Grant_Application__c a = apps[0];

        // Application headline
        card.applicationName = a.Name;
        card.status          = a.Status__c;
        card.readinessPct    = a.Readiness_Pct__c == null ? 0 : Integer.valueOf(a.Readiness_Pct__c);
        card.totalItems      = a.Total_Items__c == null ? 0 : Integer.valueOf(a.Total_Items__c);
        card.completedItems  = a.Completed_Items__c == null ? 0 : Integer.valueOf(a.Completed_Items__c);
        card.targetDeadline  = a.Target_Deadline__c;
        card.executiveSummary = a.Executive_Summary_Draft__c;
        card.caseNumber      = a.Escalated_Case__r != null ? a.Escalated_Case__r.CaseNumber : null;

        // Business profile
        if (a.Business__r != null) {
            card.businessName    = a.Business__r.Name;
            card.operatingState  = a.Business__r.Operating_State__c;
            card.employees       = a.Business__r.NumberOfEmployees;
            card.revenueBand     = a.Business__r.Revenue_Band__c;
            card.naicsCode       = a.Business__r.NAICS_Code__c;
            card.industry        = a.Business__r.Industry_Keywords__c;
            card.samActive       = a.Business__r.SAM_Registration_Active__c;
            card.samUei          = a.Business__r.SAM_UEI__c;
            List<String> tags = new List<String>();
            if (a.Business__r.Minority_Owned__c == true)   tags.add('Minority-owned');
            if (a.Business__r.Woman_Owned__c == true)      tags.add('Woman-owned');
            if (a.Business__r.Veteran_Owned__c == true)    tags.add('Veteran-owned');
            if (a.Business__r.HUBZone_Certified__c == true) tags.add('HUBZone');
            card.ownershipTags = tags;
        }

        // Grant opportunity detail
        if (a.Grant__r != null) {
            card.grantTitle       = a.Grant__r.Title__c;
            card.agency           = a.Grant__r.Agency__c;
            card.opportunityNumber = a.Grant__r.Opportunity_Number__c;
            card.fundingCategory  = a.Grant__r.Funding_Category__c;
            card.closeDate        = a.Grant__r.Close_Date__c;
            card.awardCeiling     = a.Grant__r.Award_Ceiling__c;
            card.eligibilitySummary = a.Grant__r.Eligibility_Summary__c;
            card.matchRationale   = a.Grant__r.Match_Rationale__c;
            card.sourceUrl        = a.Grant__r.Source_URL__c;
        }

        // Checklist
        List<ChecklistItem> items = new List<ChecklistItem>();
        for (Checklist_Item__c ci : a.Checklist_Items__r) {
            ChecklistItem li = new ChecklistItem();
            li.name = ci.Item_Name__c;
            li.category = ci.Category__c;
            li.isComplete = ci.Is_Complete__c == true;
            li.guidance = ci.Guidance__c;
            items.add(li);
        }
        card.checklist = items;
        return card;
    }

    public class CardData {
        @AuraEnabled public String applicationName;
        @AuraEnabled public String status;
        @AuraEnabled public Integer readinessPct;
        @AuraEnabled public Integer totalItems;
        @AuraEnabled public Integer completedItems;
        @AuraEnabled public Date targetDeadline;
        @AuraEnabled public String executiveSummary;
        @AuraEnabled public String caseNumber;
        // Business
        @AuraEnabled public String businessName;
        @AuraEnabled public String operatingState;
        @AuraEnabled public Decimal employees;
        @AuraEnabled public String revenueBand;
        @AuraEnabled public String naicsCode;
        @AuraEnabled public String industry;
        @AuraEnabled public Boolean samActive;
        @AuraEnabled public String samUei;
        @AuraEnabled public List<String> ownershipTags;
        // Grant
        @AuraEnabled public String grantTitle;
        @AuraEnabled public String agency;
        @AuraEnabled public String opportunityNumber;
        @AuraEnabled public String fundingCategory;
        @AuraEnabled public Date closeDate;
        @AuraEnabled public Decimal awardCeiling;
        @AuraEnabled public String eligibilitySummary;
        @AuraEnabled public String matchRationale;
        @AuraEnabled public String sourceUrl;
        // Checklist
        @AuraEnabled public List<ChecklistItem> checklist;

        public CardData() {
            this.ownershipTags = new List<String>();
            this.checklist = new List<ChecklistItem>();
            this.readinessPct = 0;
            this.totalItems = 0;
            this.completedItems = 0;
        }
    }

    public class ChecklistItem {
        @AuraEnabled public String name;
        @AuraEnabled public String category;
        @AuraEnabled public Boolean isComplete;
        @AuraEnabled public String guidance;
    }
}
