import { LightningElement, api } from 'lwc';
export default class NbaDemoProductsTab extends LightningElement {
    @api productsData;
    @api recordId;

    get productList() {
        return Array.isArray(this.productsData) ? this.productsData : [];
    }
    get hasProducts() {
        return this.productList.length > 0;
    }
    get products() {
        return this.productList;
    }
    get productCount() {
        return this.productList.length + ' of ' + this.productList.length + ' items';
    }
    get flowInputVariables() {
        return [{ name: 'recordId', type: 'String', value: this.recordId }];
    }
}
