/**
 * ChecklistLine
 * One document-checklist row for the Application Summary custom Lightning type.
 */
@JsonAccess(serializable='always' deserializable='always')
global class ChecklistLine {

    @AuraEnabled
    global String name;

    @AuraEnabled
    global String category;

    @AuraEnabled
    global Boolean isComplete;

    global ChecklistLine() {}

    global ChecklistLine(String name, String category, Boolean isComplete) {
        this.name = name;
        this.category = category;
        this.isComplete = isComplete;
    }
}