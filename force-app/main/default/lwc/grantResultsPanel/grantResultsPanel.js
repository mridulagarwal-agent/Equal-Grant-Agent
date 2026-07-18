import { LightningElement, api, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { NavigationMixin } from 'lightning/navigation';
import getMatchedGrants from '@salesforce/apex/GrantsGovController.getMatchedGrants';

export default class GrantResultsPanel extends NavigationMixin(LightningElement) {
    @api recordId;
    @api accountId;

    @track grants = [];
    @track error;
    @track isLoading = true;
    @track liveMode = true;
    wiredResult;

    get resolvedAccountId() {
        return this.accountId || this.recordId;
    }

    get statusMessage() {
        if (this.isLoading) return 'Loading your grant matches.';
        if (this.error) return 'We hit an error loading grants. Please try again.';
        if (!this.grants.length) return 'No matches yet. Complete your profile to see grants.';
        const src = this.liveMode ? 'Live from Grants.gov.' : 'Showing cached matches.';
        const matchWord = this.grants.length === 1 ? 'match' : 'matches';
        return `${this.grants.length} ${matchWord} found. ${src}`;
    }

    get hasGrants() {
        return this.grants && this.grants.length > 0;
    }

    get isEmpty() {
        return !this.isLoading && !this.error && !this.hasGrants;
    }

    @wire(getMatchedGrants, { accountId: '$resolvedAccountId' })
    wiredGrants(result) {
        this.wiredResult = result;
        this.isLoading = false;
        if (result.data) {
            this.liveMode = result.data.liveData !== false;
            this.grants = (result.data.grants || []).map((g, idx) => ({
                ...g,
                domId: `grant-card-${idx}`,
                hintId: `grant-card-${idx}-hint`,
                daysToCloseLabel: this.formatDays(g.daysToClose)
            }));
            this.error = undefined;
        } else if (result.error) {
            this.error = this.reduceError(result.error);
            this.grants = [];
        }
    }

    formatDays(d) {
        if (d === null || d === undefined) return 'TBD';
        if (d < 0) return 'Closed';
        if (d === 0) return 'Closes today';
        return `${d} day${d === 1 ? '' : 's'} left`;
    }

    reduceError(e) {
        if (Array.isArray(e.body)) return e.body.map((b) => b.message).join(', ');
        if (e.body && e.body.message) return e.body.message;
        return e.message || 'Unknown error';
    }

    handleApply(event) {
        const grantId = event.currentTarget.dataset.grantId;
        this.dispatchEvent(
            new CustomEvent('apply', {
                detail: { grantId, accountId: this.resolvedAccountId },
                bubbles: true,
                composed: true
            })
        );
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Grant_Application__c',
                actionName: 'new'
            },
            state: {
                defaultFieldValues: `Grant__c=${grantId},Business__c=${this.resolvedAccountId}`
            }
        });
    }

    handleRefresh() {
        this.isLoading = true;
        return refreshApex(this.wiredResult).then(() => {
            this.isLoading = false;
        });
    }
}