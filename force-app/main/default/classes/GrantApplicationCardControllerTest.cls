@isTest
private class GrantApplicationCardControllerTest {

    @isTest
    static void returnsCardWithBusinessGrantAndChecklist() {
        Account biz = new Account(
            Name = 'Buckeye Semiconductors',
            Operating_State__c = 'OH',
            NumberOfEmployees = 20,
            Woman_Owned__c = true,
            SAM_Registration_Active__c = true
        );
        insert biz;

        Grant_Opportunity__c grant = new Grant_Opportunity__c(
            Title__c = 'CHIPS Incentives Program',
            Agency__c = 'NIST',
            Opportunity_Number__c = 'NIST-CHIPS-01',
            Award_Ceiling__c = 100000
        );
        insert grant;

        Grant_Application__c app = new Grant_Application__c(
            Business__c = biz.Id,
            Grant__c = grant.Id,
            Status__c = 'Preparing'
        );
        insert app;

        insert new List<Checklist_Item__c>{
            new Checklist_Item__c(Application__c = app.Id, Item_Name__c = 'SAM registration',
                Category__c = 'Registration', Is_Complete__c = false, Sort_Order__c = 10),
            new Checklist_Item__c(Application__c = app.Id, Item_Name__c = 'Budget narrative',
                Category__c = 'Financial', Is_Complete__c = true, Sort_Order__c = 20)
        };

        Test.startTest();
        GrantApplicationCardController.CardData card =
            GrantApplicationCardController.getCard(app.Id);
        Test.stopTest();

        System.assertEquals('Buckeye Semiconductors', card.businessName);
        System.assertEquals('CHIPS Incentives Program', card.grantTitle);
        System.assertEquals(2, card.checklist.size());
        System.assert(card.ownershipTags.contains('Woman-owned'));
    }

    @isTest
    static void nullIdReturnsEmptyCard() {
        Test.startTest();
        GrantApplicationCardController.CardData card =
            GrantApplicationCardController.getCard(null);
        Test.stopTest();
        System.assertEquals(0, card.checklist.size());
        System.assertEquals(null, card.grantTitle);
    }
}
