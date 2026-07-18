/**
 * ChecklistController
 * @AuraEnabled facade for the checklistTracker LWC.
 */
public with sharing class ChecklistController {

    @AuraEnabled(cacheable=true)
    public static List<Checklist_Item__c> getChecklist(Id applicationId) {
        if (applicationId == null) return new List<Checklist_Item__c>();
        return [
            SELECT Id, Item_Name__c, Category__c, Is_Complete__c,
                   Due_Date__c, Guidance__c, Source__c, Sort_Order__c
            FROM Checklist_Item__c
            WHERE Application__c = :applicationId
            ORDER BY Category__c ASC, Sort_Order__c ASC, Item_Name__c ASC
            LIMIT 200
        ];
    }
}