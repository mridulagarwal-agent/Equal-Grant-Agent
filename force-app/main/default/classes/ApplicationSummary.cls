/**
 * ApplicationSummary
 * The output data structure surfaced by the "Get Application Summary" agent action and
 * rendered by the applicationSummary custom Lightning type / LWC. Holds the grant
 * application's headline details plus its document checklist.
 */
@JsonAccess(serializable='always' deserializable='always')
global class ApplicationSummary {

    @AuraEnabled
    global String applicationName;

    @AuraEnabled
    global String businessName;

    @AuraEnabled
    global String grantTitle;

    @AuraEnabled
    global String agency;

    @AuraEnabled
    global String status;

    @AuraEnabled
    global Integer readinessPct;

    @AuraEnabled
    global Integer totalItems;

    @AuraEnabled
    global Integer completedItems;

    @AuraEnabled
    global String executiveSummary;

    @AuraEnabled
    global List<ChecklistLine> checklist;

    global ApplicationSummary() {
        this.checklist = new List<ChecklistLine>();
    }
}