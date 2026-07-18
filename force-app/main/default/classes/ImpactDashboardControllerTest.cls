@IsTest
private class ImpactDashboardControllerTest {

    @TestSetup
    static void setup() {
        // Businesses with a mix of ownership flags.
        List<Account> accts = new List<Account>{
            new Account(Name='Alpha Solar', Woman_Owned__c=true, Veteran_Owned__c=true, Operating_State__c='CA'),
            new Account(Name='Beta Foods', Minority_Owned__c=true, Operating_State__c='TX'),
            new Account(Name='Gamma Health', Woman_Owned__c=true, HUBZone_Certified__c=true, Operating_State__c='NY')
        };
        insert accts;

        // Matched grant opportunities with award ceilings.
        List<Grant_Opportunity__c> grants = new List<Grant_Opportunity__c>{
            new Grant_Opportunity__c(Opportunity_Number__c='G-1', Title__c='Solar Fund',
                Agency__c='DOE', Award_Ceiling__c=100000, Matched_Account__c=accts[0].Id,
                Last_Refreshed__c=Datetime.now()),
            new Grant_Opportunity__c(Opportunity_Number__c='G-2', Title__c='Food Fund',
                Agency__c='USDA', Award_Ceiling__c=50000, Matched_Account__c=accts[1].Id,
                Last_Refreshed__c=Datetime.now())
        };
        insert grants;

        // Applications + checklist items.
        List<Grant_Application__c> apps = new List<Grant_Application__c>{
            new Grant_Application__c(Business__c=accts[0].Id, Grant__c=grants[0].Id, Status__c='Preparing'),
            new Grant_Application__c(Business__c=accts[1].Id, Grant__c=grants[1].Id, Status__c='Docs_Ready')
        };
        insert apps;

        insert new List<Checklist_Item__c>{
            new Checklist_Item__c(Application__c=apps[0].Id, Item_Name__c='SAM registration',
                Category__c='Registration', Is_Complete__c=true, Sort_Order__c=10),
            new Checklist_Item__c(Application__c=apps[0].Id, Item_Name__c='Budget narrative',
                Category__c='Financial', Is_Complete__c=false, Sort_Order__c=20)
        };
    }

    @IsTest
    static void getImpactData_returnsKpisAndCharts() {
        Test.startTest();
        ImpactDashboardController.ImpactData d = ImpactDashboardController.getImpactData();
        Test.stopTest();

        System.assertEquals(2, d.grantsMatched, 'two matched grants');
        System.assertEquals(150000, d.potentialCapital, 'sum of ceilings');
        System.assertEquals(2, d.applicationsInProgress, 'both apps in progress');
        System.assertEquals(4, d.ownership.size(), 'four ownership rows');
        System.assertNotEquals(null, d.matchesByOperatingState, 'operating-state breakdown should be returned');
        System.assert(d.matchesByOperatingState.size() >= 1, 'at least one operating state with apps');
        System.assert(d.matchesByMonth.size() >= 1, 'at least one month with apps');
    }

    @IsTest
    static void getRecentApplications_returnsCardsWithChecklist() {
        Test.startTest();
        List<ImpactDashboardController.ApplicationCard> cards =
            ImpactDashboardController.getRecentApplications();
        Test.stopTest();

        System.assert(cards.size() >= 2, 'at least two application cards');
        Boolean foundChecklist = false;
        for (ImpactDashboardController.ApplicationCard c : cards) {
            if (c.checklist != null && !c.checklist.isEmpty()) foundChecklist = true;
        }
        System.assert(foundChecklist, 'at least one card has checklist rows');
    }
}