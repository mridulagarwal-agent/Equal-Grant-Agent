/**
 * FetchGrantDetailAction
 * Invocable wrapper around GrantsGovService.fetchOpportunity for Agentforce / Flow.
 */
public with sharing class FetchGrantDetailAction {

    @InvocableMethod(
        label='Fetch Grant Opportunity Detail'
        description='Fetches Grants.gov fetchOpportunity detail and enriches the cached record.'
        category='EqualStart')
    public static List<GrantsGovService.FetchResult> run(List<GrantsGovService.FetchRequest> reqs) {
        return GrantsGovService.fetchOpportunity(reqs);
    }
}