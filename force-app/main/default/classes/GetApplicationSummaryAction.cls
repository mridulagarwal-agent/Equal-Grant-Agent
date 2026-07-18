/**
 * GetApplicationSummaryAction
 * Invocable agent action: given a Grant Application Id, returns an ApplicationSummary
 * (headline details + document checklist). The output is rendered by the
 * applicationSummary custom Lightning type -> applicationSummary LWC.
 *
 * NOTE: not yet wired into the agent - registered as a standalone action for later use.
 */
global with sharing class GetApplicationSummaryAction {

    @JsonAccess(serializable='always' deserializable='always')
    global class Request {
        @InvocableVariable(label='Grant Application Id' required=true)
        global String applicationId;
    }

    @JsonAccess(serializable='always' deserializable='always')
    global class Response {
        @InvocableVariable
        global ApplicationSummary summary;

        // Plain-text, pre-formatted summary. Reliable fallback the agent can present verbatim
        // in channels (like embedded web chat) where the custom Lightning type card does not render.
        @InvocableVariable
        global String summaryText;
    }

    @InvocableMethod(
        label='Get Application Summary'
        description='Returns a grant application summary and its document checklist for rendering.'
        category='EqualGrant')
    global static List<Response> getSummary(List<Request> reqs) {
        List<Response> out = new List<Response>();
        for (Request req : reqs) {
            Response r = new Response();
            r.summary = buildSummary(req.applicationId);
            r.summaryText = buildSummaryText(r.summary);
            out.add(r);
        }
        return out;
    }

    private static ApplicationSummary buildSummary(String applicationId) {
        ApplicationSummary s = new ApplicationSummary();
        if (String.isBlank(applicationId)) {
            return s;
        }

        List<Grant_Application__c> apps = [
            SELECT Id, Name, Status__c, Readiness_Pct__c, Total_Items__c, Completed_Items__c,
                   Executive_Summary_Draft__c,
                   Business__r.Name, Grant__r.Title__c, Grant__r.Agency__c,
                   (SELECT Item_Name__c, Category__c, Is_Complete__c
                    FROM Checklist_Items__r
                    ORDER BY Category__c, Sort_Order__c
                    LIMIT 50)
            FROM Grant_Application__c
            WHERE Id = :applicationId
            LIMIT 1
        ];
        if (apps.isEmpty()) {
            return s;
        }

        Grant_Application__c a = apps[0];
        s.applicationName = a.Name;
        s.businessName    = a.Business__r != null ? a.Business__r.Name : 'Business';
        s.grantTitle      = a.Grant__r != null ? a.Grant__r.Title__c : 'Grant';
        s.agency          = a.Grant__r != null ? a.Grant__r.Agency__c : '';
        s.status          = a.Status__c;
        s.readinessPct    = a.Readiness_Pct__c == null ? 0 : Integer.valueOf(a.Readiness_Pct__c);
        s.totalItems      = a.Total_Items__c == null ? 0 : Integer.valueOf(a.Total_Items__c);
        s.completedItems  = a.Completed_Items__c == null ? 0 : Integer.valueOf(a.Completed_Items__c);
        s.executiveSummary = a.Executive_Summary_Draft__c;

        for (Checklist_Item__c ci : a.Checklist_Items__r) {
            s.checklist.add(new ChecklistLine(ci.Item_Name__c, ci.Category__c, ci.Is_Complete__c));
        }
        return s;
    }

    // Build a clean, human-readable text block the agent can present verbatim. Groups
    // checklist items by category and marks each done/pending. No markdown tables.
    private static String buildSummaryText(ApplicationSummary s) {
        if (s == null || String.isBlank(s.grantTitle)) {
            return 'No application details are available yet.';
        }
        String nl = '\n';
        String statusLabel = labelStatus(s.status);
        List<String> lines = new List<String>();
        lines.add('📄 ' + s.grantTitle);
        lines.add(s.businessName + ' • ' + s.agency);
        lines.add('Application ' + s.applicationName + ' — ' + statusLabel);
        lines.add('Readiness: ' + s.readinessPct + '% (' + s.completedItems + ' of ' + s.totalItems + ' documents ready)');

        if (s.checklist != null && !s.checklist.isEmpty()) {
            lines.add('');
            lines.add('Document Checklist');
            String currentCat = null;
            for (ChecklistLine c : s.checklist) {
                String cat = String.isBlank(c.category) ? 'Other' : c.category;
                if (currentCat != cat) {
                    lines.add('');
                    lines.add(cat.toUpperCase());
                    currentCat = cat;
                }
                String mark = c.isComplete ? '✓' : '☐';
                lines.add('  ' + mark + ' ' + c.name);
            }
        }
        return String.join(lines, nl);
    }

    private static String labelStatus(String status) {
        if (status == 'Docs_Ready') return 'Docs ready';
        if (String.isBlank(status)) return 'Preparing';
        return status;
    }
}