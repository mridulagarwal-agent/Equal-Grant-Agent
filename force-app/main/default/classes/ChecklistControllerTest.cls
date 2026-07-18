@IsTest
private class ChecklistControllerTest {

    @IsTest
    static void getChecklist_ordersByCategoryAndSort() {
        Account biz = new Account(Name = 'Test Biz');
        insert biz;

        Grant_Opportunity__c grant = new Grant_Opportunity__c(
            Opportunity_Number__c = 'GRT-1', Title__c = 'Test Grant');
        insert grant;

        Grant_Application__c app = new Grant_Application__c(
            Business__c = biz.Id, Grant__c = grant.Id, Status__c = 'Preparing');
        insert app;

        insert new List<Checklist_Item__c>{
            new Checklist_Item__c(Application__c = app.Id, Item_Name__c = 'Financials',
                Category__c = 'Financial', Sort_Order__c = 10),
            new Checklist_Item__c(Application__c = app.Id, Item_Name__c = 'SAM UEI',
                Category__c = 'Registration', Sort_Order__c = 10),
            new Checklist_Item__c(Application__c = app.Id, Item_Name__c = 'EIN Letter',
                Category__c = 'Registration', Sort_Order__c = 20)
        };

        Test.startTest();
        List<Checklist_Item__c> items = ChecklistController.getChecklist(app.Id);
        Test.stopTest();

        System.assertEquals(3, items.size());
        // Picklists order by value-set definition: Registration comes before Financial
        System.assertEquals('Registration', items[0].Category__c);
        System.assertEquals('Registration', items[1].Category__c);
        System.assertEquals('Financial',    items[2].Category__c);
        System.assertEquals('SAM UEI',      items[0].Item_Name__c, 'sort order 10 before 20');
        System.assertEquals('EIN Letter',   items[1].Item_Name__c);
    }

    @IsTest
    static void getChecklist_nullReturnsEmpty() {
        Test.startTest();
        List<Checklist_Item__c> items = ChecklistController.getChecklist(null);
        Test.stopTest();
        System.assertEquals(0, items.size());
    }
}