@IsTest
private class GetApplicationSummaryActionTest {

    @IsTest
    static void getSummary_returnsSummaryWithChecklist() {
        Account biz = new Account(Name='Whitfield Solar LLC', Woman_Owned__c=true);
        insert biz;
        Grant_Opportunity__c g = new Grant_Opportunity__c(
            Opportunity_Number__c='VETBIZ-26-011', Title__c='Veteran Innovation Fund',
            Agency__c='SBA', Matched_Account__c=biz.Id, Last_Refreshed__c=Datetime.now());
        insert g;
        Grant_Application__c app = new Grant_Application__c(
            Business__c=biz.Id, Grant__c=g.Id, Status__c='Docs_Ready',
            Executive_Summary_Draft__c='This is the AI-drafted summary.');
        insert app;
        insert new List<Checklist_Item__c>{
            new Checklist_Item__c(Application__c=app.Id, Item_Name__c='SAM registration',
                Category__c='Registration', Is_Complete__c=true, Sort_Order__c=10),
            new Checklist_Item__c(Application__c=app.Id, Item_Name__c='Budget narrative',
                Category__c='Financial', Is_Complete__c=false, Sort_Order__c=20)
        };

        GetApplicationSummaryAction.Request req = new GetApplicationSummaryAction.Request();
        req.applicationId = app.Id;

        Test.startTest();
        List<GetApplicationSummaryAction.Response> res =
            GetApplicationSummaryAction.getSummary(new List<GetApplicationSummaryAction.Request>{ req });
        Test.stopTest();

        ApplicationSummary s = res[0].summary;
        System.assertEquals('Whitfield Solar LLC', s.businessName);
        System.assertEquals('Veteran Innovation Fund', s.grantTitle);
        System.assertEquals('Docs_Ready', s.status);
        System.assertEquals('This is the AI-drafted summary.', s.executiveSummary);
        System.assertEquals(2, s.checklist.size());
        System.assertEquals('SAM registration', s.checklist[0].name);
    }

    @IsTest
    static void getSummary_blankId_returnsEmpty() {
        GetApplicationSummaryAction.Request req = new GetApplicationSummaryAction.Request();
        req.applicationId = '';

        Test.startTest();
        List<GetApplicationSummaryAction.Response> res =
            GetApplicationSummaryAction.getSummary(new List<GetApplicationSummaryAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(0, res[0].summary.checklist.size());
    }
}