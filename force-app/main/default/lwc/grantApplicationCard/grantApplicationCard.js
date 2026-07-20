import { LightningElement, api, wire, track } from 'lwc';
import getCard from '@salesforce/apex/GrantApplicationCardController.getCard';

const STATUS_LABELS = {
    Preparing: 'Preparing',
    Docs_Ready: 'Docs ready',
    Submitted: 'Submitted',
    Awarded: 'Awarded',
    Declined: 'Declined',
    Withdrawn: 'Withdrawn'
};

export default class GrantApplicationCard extends LightningElement {
    // recordId is injected automatically when placed on a record page.
    @api recordId;

    @track app;
    @track business;
    @track grant;
    @track checklist = [];
    error;
    isLoading = true;

    @wire(getCard, { applicationId: '$recordId' })
    wired({ data, error }) {
        if (data) {
            const pct = data.readinessPct || 0;
            this.app = {
                applicationName: data.applicationName,
                statusLabel: STATUS_LABELS[data.status] || data.status,
                statusClass: this.statusClass(data.status),
                readinessPct: pct,
                readinessLabel: `${data.completedItems || 0} of ${data.totalItems || 0} documents ready`,
                progressStyle: `width:${pct}%;`,
                executiveSummary: data.executiveSummary,
                caseNumber: data.caseNumber
            };
            this.business = {
                name: data.businessName,
                operatingState: data.operatingState,
                employees: data.employees,
                revenueBand: data.revenueBand,
                naicsCode: data.naicsCode,
                industry: data.industry,
                samActive: data.samActive,
                samUei: data.samUei,
                ownershipTags: (data.ownershipTags || []).map((t) => ({ key: t, label: t }))
            };
            this.grant = {
                title: data.grantTitle,
                agency: data.agency,
                opportunityNumber: data.opportunityNumber,
                fundingCategory: data.fundingCategory,
                closeDate: data.closeDate,
                awardCeiling: data.awardCeiling,
                eligibilitySummary: data.eligibilitySummary,
                matchRationale: data.matchRationale,
                sourceUrl: data.sourceUrl
            };
            this.checklist = this.groupChecklist(data.checklist || []);
            this.error = undefined;
        } else if (error) {
            this.error = this.reduce(error);
        }
        this.isLoading = false;
    }

    // Group checklist items by category for a tidy internal view.
    groupChecklist(items) {
        const groups = {};
        const order = [];
        items.forEach((c, i) => {
            const cat = (c.category || 'Other').toUpperCase();
            if (!groups[cat]) {
                groups[cat] = { key: cat, category: cat, items: [] };
                order.push(cat);
            }
            groups[cat].items.push({
                key: `${i}-${c.name}`,
                name: c.name,
                guidance: c.guidance,
                iconName: c.isComplete ? 'utility:success' : 'utility:routing_offline',
                iconVariant: c.isComplete ? 'success' : '',
                rowClass: c.isComplete ? 'es-item es-item_done' : 'es-item'
            });
        });
        return order.map((cat) => groups[cat]);
    }

    statusClass(status) {
        if (status === 'Docs_Ready' || status === 'Submitted' || status === 'Awarded') {
            return 'es-pill es-pill_success';
        }
        if (status === 'Declined' || status === 'Withdrawn') {
            return 'es-pill es-pill_muted';
        }
        return 'es-pill';
    }

    get hasApp() {
        return this.app && this.grant && this.grant.title;
    }
    get noApp() {
        return !this.isLoading && !this.hasApp;
    }
    get hasChecklist() {
        return this.checklist && this.checklist.length > 0;
    }
    get hasExecutiveSummary() {
        return this.app && this.app.executiveSummary;
    }
    get hasOwnershipTags() {
        return this.business && this.business.ownershipTags && this.business.ownershipTags.length > 0;
    }
    get hasCaseNumber() {
        return this.app && this.app.caseNumber;
    }

    reduce(error) {
        if (Array.isArray(error.body)) return error.body.map((e) => e.message).join(', ');
        if (error.body && error.body.message) return error.body.message;
        return error.message || 'Unknown error';
    }
}
