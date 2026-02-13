import { LightningElement, api } from 'lwc';
export default class NbaDemoPayrollTab extends LightningElement {
    @api payrollTabData;

    get isReadyToRun() {
        return this.payrollTabData?.isReadyToRun;
    }
    get readyBannerClass() {
        return this.isReadyToRun
            ? 'ready-banner ready'
            : 'ready-banner not-ready';
    }
    get readyMessage() {
        return this.isReadyToRun
            ? 'Customer is Ready to Run Payroll \uD83D\uDD25'
            : 'Customer Payroll Setup In Progress';
    }
    get readySubtext() {
        return this.isReadyToRun
            ? 'Company is fully implemented in Check and is able to run payroll within Homebase!'
            : 'The customer is still going through the payroll implementation process.';
    }
    get formattedFirstPayday() {
        if (!this.payrollTabData?.firstPayday) return '\u2014';
        return this.payrollTabData.firstPayday;
    }
    get riskLevelClass() {
        const level =
            this.payrollTabData?.payrollRiskLevel?.toLowerCase() || '';
        if (level.includes('high')) return 'risk-badge risk-high';
        if (level.includes('medium')) return 'risk-badge risk-medium';
        return 'risk-badge risk-low';
    }

    /* Summary getters */
    get inceptionSwitcher() {
        return this.payrollTabData?.inceptionSwitcher || '\u2014';
    }
    get employeeCount() {
        return this.payrollTabData?.employeeCount != null
            ? String(this.payrollTabData.employeeCount)
            : '\u2014';
    }
    get predictedMrr() {
        return this.payrollTabData?.predictedMrr != null
            ? '$' + Number(this.payrollTabData.predictedMrr).toFixed(2)
            : '\u2014';
    }

    /* Current Next Step */
    get currentNextStep() {
        return this.payrollTabData?.currentNextStep || '\u2014';
    }

    /* Progression getters */
    get payrollRiskLevel() {
        return this.payrollTabData?.payrollRiskLevel || '\u2014';
    }
    get lastProgressionTime() {
        return this.payrollTabData?.lastProgressionTime || '\u2014';
    }
    get currentLinearFlowPage() {
        return this.payrollTabData?.currentLinearFlowPage || '\u2014';
    }
    get lastPayrollEngagement() {
        return this.payrollTabData?.lastPayrollEngagement || '\u2014';
    }
    get payrollEngagementType() {
        return this.payrollTabData?.payrollEngagementType || '\u2014';
    }
    get fedAuthFinish() {
        return this.payrollTabData?.fedAuthFinish || '\u2014';
    }
    get bankConnectFinish() {
        return this.payrollTabData?.bankConnectFinish || '\u2014';
    }
    get paySchedFinish() {
        return this.payrollTabData?.paySchedFinish || '\u2014';
    }

    /* Check Information getters */
    get checkInfoNeeded() {
        return this.payrollTabData?.checkInfoNeeded || '\u2014';
    }
    get kybStatus() {
        return this.payrollTabData?.kybStatus || '\u2014';
    }
    get onboardStatus() {
        return this.payrollTabData?.onboardStatus || '\u2014';
    }
    get implementationStatus() {
        return this.payrollTabData?.implementationStatus || '\u2014';
    }
    get payrollStatus() {
        return this.payrollTabData?.payrollStatus || '\u2014';
    }
    get blockedReason() {
        return this.payrollTabData?.blockedReason || '\u2014';
    }

    /* Activity getters */
    get nextStepDate() {
        return this.payrollTabData?.nextStepDate || '\u2014';
    }
    get nextStep() {
        return this.payrollTabData?.nextStep || '\u2014';
    }
    get futureFollowUpDate() {
        return this.payrollTabData?.futureFollowUpDate || '\u2014';
    }
    get futureFollowUpReason() {
        return this.payrollTabData?.futureFollowUpReason || '\u2014';
    }
    get lastCallDateTime() {
        return this.payrollTabData?.lastCallDateTime || '\u2014';
    }
    get lastCallOutcome() {
        return this.payrollTabData?.lastCallOutcome || '\u2014';
    }
    get nbaCallCount() {
        return this.payrollTabData?.nbaCallCount != null
            ? String(this.payrollTabData.nbaCallCount)
            : '\u2014';
    }
}
