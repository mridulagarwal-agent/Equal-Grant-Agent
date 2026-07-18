/**
 * SearchGrantsAction
 * Invocable wrapper around GrantsGovService.searchGrants for Agentforce / Flow.
 */
public with sharing class SearchGrantsAction {

    @InvocableMethod(
        label='Search Federal Grants'
        description='Queries Grants.gov search2 for the given account and upserts matches.'
        category='EqualStart')
    public static List<GrantsGovService.SearchResult> run(List<GrantsGovService.SearchRequest> reqs) {
        return GrantsGovService.searchGrants(reqs);
    }
}