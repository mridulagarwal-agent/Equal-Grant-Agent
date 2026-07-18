import { LightningElement, wire, track } from 'lwc';
import isGuest from '@salesforce/user/isGuest';
import getImpactData from '@salesforce/apex/ImpactDashboardController.getImpactData';
import getRecentApplications from '@salesforce/apex/ImpactDashboardController.getRecentApplications';

const OWNERSHIP_COLORS = ['#24406b', '#e0a13c', '#2f7d4f', '#b5561f'];

export default class EqualStartImpact extends LightningElement {
    @track kpis;
    @track ownership = [];
    @track states = [];
    @track apps = [];
    @track error;
    isLoading = true;

    @wire(getImpactData)
    wiredImpact({ data, error }) {
        if (data) {
            this.kpis = {
                businessesHelped: data.businessesHelped,
                grantsMatched: data.grantsMatched,
                potentialCapital: this.formatCapital(data.potentialCapital),
                applicationsInProgress: data.applicationsInProgress,
                docsReady: data.docsReady
            };
            this.ownership = (data.ownership || []).map((o, i) => ({
                ...o,
                key: o.label,
                barStyle: `width:${o.percent}%;background:${OWNERSHIP_COLORS[i % OWNERSHIP_COLORS.length]};`
            }));
            const stateMatches = Array.isArray(data.matchesByOperatingState)
                ? data.matchesByOperatingState
                : Array.isArray(data.matchesByState)
                    ? data.matchesByState
                    : [];
            const maxCount = Math.max(1, ...stateMatches.map((m) => Number(m.count || m.matches || 0)));
            const lastIdx = stateMatches.length - 1;
            this.states = stateMatches.map((m, i) => {
                const stateName = m.operatingState || m.stateLabel || m.state || m.stateName || m.label || m.name || `State ${i + 1}`;
                return {
                    key: stateName,
                    stateLabel: stateName,
                    count: Number(m.count || m.matches || 0),
                    barStyle: `height:${Math.round((Number(m.count || m.matches || 0) / maxCount) * 150)}px;`
                        + (i === lastIdx ? 'background:#e0a13c;' : 'background:#24406b;')
                };
            });
            this.error = undefined;
        } else if (error) {
            this.error = this.reduce(error);
        }
        this.isLoading = false;
    }

    @wire(getRecentApplications)
    wiredApps({ data, error }) {
        if (data) {
            this.apps = data.map((a) => ({
                ...a,
                progressStyle: `width:${a.readinessPct}%;`,
                readinessLabel: `${a.completedItems} of ${a.totalItems} documents ready`,
                statusClass: this.statusClass(a.status),
                checklist: (a.checklist || []).map((c) => ({
                    ...c,
                    iconName: c.isComplete ? 'utility:check' : 'utility:record',
                    iconVariant: c.isComplete ? 'success' : '',
                    rowClass: c.isComplete ? 'es-check es-check_done' : 'es-check'
                }))
            }));
        } else if (error) {
            this.error = this.reduce(error);
        }
    }

    get hasApps() {
        return this.apps && this.apps.length > 0;
    }

    // Recent grant applications are hidden from unauthenticated (guest) visitors -
    // they contain business-specific detail. Only shown to logged-in users.
    get showRecentApps() {
        return !isGuest && this.hasApps;
    }

    get hasStates() {
        return this.states && this.states.length > 0;
    }

    formatCapital(v) {
        if (!v) return '$0';
        if (v >= 1000000) return `$${(v / 1000000).toFixed(1)}M`;
        if (v >= 1000) return `$${Math.round(v / 1000)}K`;
        return `$${v}`;
    }

    statusClass(status) {
        if (status === 'Docs_Ready') return 'slds-badge slds-theme_success';
        if (status === 'Submitted' || status === 'Awarded') return 'slds-badge slds-theme_success';
        return 'slds-badge';
    }

    reduce(error) {
        if (Array.isArray(error.body)) return error.body.map((e) => e.message).join(', ');
        if (error.body && error.body.message) return error.body.message;
        return error.message || 'Unknown error';
    }
}