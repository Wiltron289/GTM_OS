import { LightningElement, api } from 'lwc';
export default class NbaDemoProductsTab extends LightningElement {
    @api productsData;
    @api recordId;

    get hasProducts() {
        return this.productsData?.products?.length > 0;
    }
    get products() {
        return this.productsData?.products || [];
    }
    get currentAmount() {
        const amt = this.productsData?.currentAmount || 0;
        return '$' + amt.toFixed(2);
    }
    get attainedAmount() {
        const amt = this.productsData?.attainedAmount || 0;
        return '$' + amt.toFixed(2);
    }
    get productCount() {
        const products = this.productsData?.products || [];
        return products.length + ' of ' + products.length + ' items';
    }
    get flowInputVariables() {
        return [{ name: 'recordId', type: 'String', value: this.recordId }];
    }
}
