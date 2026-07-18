import { LightningElement, api, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { updateRecord } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getChecklist from '@salesforce/apex/ChecklistController.getChecklist';
import CHECKLIST_ID from '@salesforce/schema/Checklist_Item__c.Id';
import CHECKLIST_DONE from '@salesforce/schema/Checklist_Item__c.Is_Complete__c';

const GROUP_ORDER = ['Registration', 'Certification', 'Financial', 'Narrative', 'Legal', 'Other'];

export default class ChecklistTracker extends LightningElement {
    @api recordId;
    @api applicationId;

    @track groups = [];
    @track totalCount = 0;
    @track doneCount = 0;
    @track isBusy = false;
    wiredResult;

    get resolvedAppId() {
        return this.applicationId || this.recordId;
    }
    get progressPct() {
        return this.totalCount === 0 ? 0 : Math.round((this.doneCount * 100) / this.totalCount);
    }
    get progressLabel() {
        return `${this.progressPct}% complete`;
    }
    get progressBarStyle() {
        return `width: ${this.progressPct}%;`;
    }
    get isDone() {
        return this.totalCount > 0 && this.doneCount === this.totalCount;
    }
    get hasItems() {
        return this.totalCount > 0;
    }
    get showEmptyState() {
        return this.totalCount === 0;
    }
    get statusAnnouncement() {
        if (this.isBusy) return 'Saving your update.';
        if (this.isDone) return 'All documents ready. You are cleared to submit.';
        return `${this.doneCount} of ${this.totalCount} documents complete.`;
    }

    @wire(getChecklist, { applicationId: '$resolvedAppId' })
    wiredChecklist(result) {
        this.wiredResult = result;
        if (result.data) {
            const items = result.data;
            this.totalCount = items.length;
            this.doneCount = items.filter((i) => i.Is_Complete__c).length;
            const byCat = {};
            items.forEach((i) => {
                const cat = i.Category__c || 'Other';
                if (!byCat[cat]) byCat[cat] = [];
                byCat[cat].push({
                    id: i.Id,
                    name: i.Item_Name__c,
                    guidance: i.Guidance__c,
                    dueDate: i.Due_Date__c,
                    done: i.Is_Complete__c,
                    inputId: `chk-${i.Id}`,
                    hintId: `chk-${i.Id}-hint`
                });
            });
            this.groups = GROUP_ORDER.filter((c) => byCat[c]).map((c) => ({
                label: c,
                key: c,
                items: byCat[c]
            }));
        }
    }

    async handleToggle(event) {
        const id = event.target.dataset.id;
        const done = event.target.checked;
        this.isBusy = true;
        try {
            const fields = {};
            fields[CHECKLIST_ID.fieldApiName] = id;
            fields[CHECKLIST_DONE.fieldApiName] = done;
            await updateRecord({ fields });
            await refreshApex(this.wiredResult);
        } catch (err) {
            event.target.checked = !done;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Update failed',
                    message: (err && err.body && err.body.message) || 'Please try again.',
                    variant: 'error'
                })
            );
        } finally {
            this.isBusy = false;
        }
    }
}