import { LightningElement, api, track } from 'lwc';

const STATUS_LABELS = {
    Preparing: 'Preparing',
    Docs_Ready: 'Docs ready',
    Submitted: 'Submitted',
    Awarded: 'Awarded',
    Declined: 'Declined',
    Withdrawn: 'Withdrawn'
};

export default class ApplicationSummary extends LightningElement {
    _value;
    @track summary = {};
    @track checklist = [];
    summaryExpanded = false;

    // The custom Lightning type passes the ApplicationSummary object in `value`.
    @api
    get value() {
        return this._value;
    }
    set value(v) {
        this._value = v;
        this.hydrate(v);
    }

    hydrate(v) {
        if (!v) {
            this.summary = {};
            this.checklist = [];
            return;
        }
        const total = v.totalItems || 0;
        const done = v.completedItems || 0;
        const pct = v.readinessPct || 0;

        this.summary = {
            applicationName: v.applicationName,
            businessName: v.businessName,
            agency: v.agency,
            grantTitle: v.grantTitle,
            statusLabel: STATUS_LABELS[v.status] || v.status,
            statusClass: this.statusClass(v.status),
            readinessPct: pct,
            readinessLabel: `${done} of ${total} ready`,
            progressStyle: `width:${pct}%;`,
            executiveSummary: v.executiveSummary
        };
        this.checklist = (v.checklist || []).map((c, i) => ({
            key: `${i}-${c.name}`,
            name: c.name,
            category: (c.category || '').toUpperCase(),
            iconName: c.isComplete ? 'utility:success' : 'utility:routing_offline',
            iconVariant: c.isComplete ? 'success' : '',
            rowClass: c.isComplete ? 'es-item es-item_done' : 'es-item'
        }));
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

    get hasSummary() {
        return this.summary && this.summary.grantTitle;
    }
    get noSummary() {
        return !this.hasSummary;
    }
    get hasExecutiveSummary() {
        return this.summary && this.summary.executiveSummary;
    }
    get hasChecklist() {
        return this.checklist && this.checklist.length > 0;
    }

    get summaryToggleLabel() {
        return this.summaryExpanded ? 'Hide' : 'Show';
    }
    get summaryBodyClass() {
        return this.summaryExpanded ? 'es-exec__body es-exec__body_open' : 'es-exec__body';
    }
    toggleSummary() {
        this.summaryExpanded = !this.summaryExpanded;
    }

    // ===== Download =====
    downloadSummary() {
        const s = this.summary || {};
        const html = this.buildDocument(s);
        const blob = new Blob([html], { type: 'text/html;charset=utf-8' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `${this.fileSafe(s.applicationName || 'grant-application')}-summary.html`;
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        URL.revokeObjectURL(url);
    }

    fileSafe(text) {
        return String(text).replace(/[^a-z0-9\-_]+/gi, '-').replace(/^-+|-+$/g, '');
    }

    esc(text) {
        return String(text == null ? '' : text)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    buildDocument(s) {
        const rows = this.checklist
            .map((c) => {
                const mark = c.rowClass.indexOf('_done') > -1 ? '&#10003;' : '&#9675;';
                const cls = c.rowClass.indexOf('_done') > -1 ? ' class="done"' : '';
                return `<tr${cls}><td class="mk">${mark}</td><td>${this.esc(c.name)}</td>` +
                    `<td class="cat">${this.esc(c.category)}</td></tr>`;
            })
            .join('');

        const execBlock = s.executiveSummary
            ? `<h2>Executive Summary</h2>
               <p class="note">AI-assisted draft &mdash; review before submitting.</p>
               <div class="exec">${this.esc(s.executiveSummary)}</div>`
            : '';

        const checklistBlock = this.checklist.length
            ? `<h2>Document Checklist</h2>
               <table>
                 <thead><tr><th></th><th>Document</th><th>Category</th></tr></thead>
                 <tbody>${rows}</tbody>
               </table>`
            : '';

        return `<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<title>${this.esc(s.grantTitle)} - Application Summary</title>
<style>
  body{font-family:'Helvetica Neue',Arial,sans-serif;color:#1c2a44;margin:2.5rem;line-height:1.5;}
  h1{color:#24406b;font-size:1.4rem;margin:0 0 .25rem;}
  .sub{color:#5c6a82;margin:0 0 .25rem;}
  .appnum{color:#9aa4b5;font-family:monospace;font-size:.85rem;}
  .status{display:inline-block;margin-left:.5rem;padding:.1rem .6rem;border-radius:99px;
    background:#e3f4ea;color:#1c6b3f;font-size:.75rem;font-weight:600;}
  .readiness{margin:1rem 0;font-weight:600;color:#24406b;}
  h2{color:#24406b;font-size:1.05rem;margin:1.6rem 0 .5rem;border-bottom:2px solid #e0a13c;
    padding-bottom:.25rem;}
  .note{font-size:.8rem;color:#6b5b2e;margin:.25rem 0 .5rem;}
  .exec{white-space:pre-wrap;background:#f6f4ef;border:1px solid #e3dccf;border-radius:8px;
    padding:1rem;}
  table{width:100%;border-collapse:collapse;font-size:.9rem;}
  th{text-align:left;color:#5c6a82;font-size:.75rem;text-transform:uppercase;
    letter-spacing:.04em;border-bottom:1px solid #e3dccf;padding:.4rem .5rem;}
  td{padding:.45rem .5rem;border-bottom:1px solid #f0ece2;vertical-align:top;}
  td.mk{width:1.5rem;color:#1c6b3f;font-size:1rem;}
  td.cat{color:#9aa4b5;font-size:.7rem;text-transform:uppercase;white-space:nowrap;}
  tr.done td:not(.mk){text-decoration:line-through;color:#6b8a72;}
  footer{margin-top:2.5rem;color:#9aa4b5;font-size:.72rem;border-top:1px solid #e3dccf;
    padding-top:.5rem;}
</style></head>
<body>
  <h1>${this.esc(s.grantTitle)}</h1>
  <p class="sub">${this.esc(s.businessName)} &middot; ${this.esc(s.agency)}</p>
  <p><span class="appnum">${this.esc(s.applicationName)}</span>
     <span class="status">${this.esc(s.statusLabel)}</span></p>
  <p class="readiness">Readiness: ${this.esc(s.readinessLabel)} (${s.readinessPct || 0}%)</p>
  ${execBlock}
  ${checklistBlock}
  <footer>Generated by EqualGrant &mdash; Agentforce for Good.</footer>
</body></html>`;
    }
}