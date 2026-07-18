@IsTest
private class GrantsGovControllerTest {

    @IsTest
    static void getMatchedGrants_returnsFormattedDisplay() {
        Account biz = new Account(Name = 'Test Biz');
        insert biz;

        insert new Grant_Opportunity__c(
            Opportunity_Number__c = 'GRT-A',
            Title__c              = 'Alpha Fund',
            Agency__c             = 'SBA',
            Award_Ceiling__c      = 100000,
            Close_Date__c         = Date.today().addDays(30),
            Match_Rationale__c    = 'veteran-owned',
            Matched_Account__c    = biz.Id,
            Last_Refreshed__c     = Datetime.now()
        );
        insert new Grant_Opportunity__c(
            Opportunity_Number__c = 'GRT-B',
            Title__c              = 'Beta Fund',
            Agency__c             = 'DOE',
            Matched_Account__c    = biz.Id,
            Last_Refreshed__c     = Datetime.now().addMinutes(-5)
        );

        Test.startTest();
        GrantsGovController.MatchedResult r = GrantsGovController.getMatchedGrants(biz.Id);
        Test.stopTest();

        System.assertEquals(2, r.grants.size());
        System.assertEquals('GRT-A', r.grants[0].opportunityNumber, 'most recent first');
        System.assertEquals('$100,000', r.grants[0].awardCeilingFormatted);
        System.assertEquals(30, r.grants[0].daysToClose);
        System.assertEquals('TBD', r.grants[1].awardCeilingFormatted);
        System.assertEquals(null, r.grants[1].daysToClose);
    }

    @IsTest
    static void getMatchedGrants_nullAccount_returnsEmpty() {
        Test.startTest();
        GrantsGovController.MatchedResult r = GrantsGovController.getMatchedGrants(null);
        Test.stopTest();
        System.assertEquals(0, r.grants.size());
        System.assertEquals(true, r.liveData);
    }
}