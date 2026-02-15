# LWC Patterns & Conventions

## Component Structure
Every LWC component has:
- `componentName.html` — template markup
- `componentName.js` — controller logic
- `componentName.js-meta.xml` — metadata config (API version, targets, visibility)
- `componentName.css` — optional styles (use SLDS classes first)
- `__tests__/componentName.test.js` — Jest test file

## Naming
- Component folders and files: camelCase (`myComponent`)
- In HTML markup: kebab-case with namespace (`c-my-component`)
- JS class: PascalCase (`export default class MyComponent`)
- Custom events: lowercase no hyphens (`customevent`, not `custom-event`)

## Reactivity
- `@api` — public properties exposed to parent components or App Builder.
- `@track` — only needed for object/array deep mutations. Primitive reactive properties don't need it.
- Reassign arrays/objects to trigger reactivity: `this.items = [...this.items, newItem]`
- Never mutate `@wire` results directly — clone data before modifying.

## Wire Adapters
```javascript
import { LightningElement, wire } from 'lwc';
import getAccounts from '@salesforce/apex/AccountController.getAccounts';

export default class MyComponent extends LightningElement {
    @wire(getAccounts, { searchKey: '$searchTerm' })
    wiredAccounts;
}
```
- Use `@wire` for declarative data access (Apex methods or LDS).
- Reactive variables use `$` prefix in wire parameters.
- `@wire` results have `{ data, error }` shape.
- Prefer **Lightning Data Service (LDS)** over Apex for simple CRUD:
  - `getRecord`, `getFieldValue`, `createRecord`, `updateRecord`, `deleteRecord`

## Imperative Apex Calls
```javascript
import getAccounts from '@salesforce/apex/AccountController.getAccounts';

async handleSearch() {
    try {
        this.accounts = await getAccounts({ searchKey: this.searchTerm });
    } catch (error) {
        this.showToast('Error', error.body.message, 'error');
    }
}
```
- Use imperative calls for user-triggered actions (button clicks, form submits).
- Always wrap in try/catch.

## Events
- Child-to-parent: `this.dispatchEvent(new CustomEvent('select', { detail: recordId }))`.
- Parent listens with `onselect` handler in template.
- Cross-DOM (unrelated components): use Lightning Message Service (LMS).

## Navigation
```javascript
import { NavigationMixin } from 'lightning/navigation';

export default class MyComponent extends NavigationMixin(LightningElement) {
    navigateToRecord(recordId) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId, objectApiName: 'Account', actionName: 'view' }
        });
    }
}
```

## Toast Notifications
```javascript
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
}
```

## Template Best Practices
- Use `lwc:if`, `lwc:elseif`, `lwc:else` (NOT deprecated `if:true`/`if:false`).
- Use `lightning-*` base components (lightning-card, lightning-datatable, lightning-input, etc.).
- Show loading spinners while data loads (`lightning-spinner`).
- Display error states with user-friendly messages.
- Use SLDS utility classes before writing custom CSS.

## Meta XML Targets
```xml
<?xml version="1.0" encoding="UTF-8"?>
<LightningComponentBundle xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>65.0</apiVersion>
    <isExposed>true</isExposed>
    <targets>
        <target>lightning__RecordPage</target>
        <target>lightning__AppPage</target>
        <target>lightning__HomePage</target>
    </targets>
</LightningComponentBundle>
```
- `lightning__RecordPage` — record pages
- `lightning__AppPage` — app pages
- `lightning__HomePage` — home page
- `lightning__FlowScreen` — flow screens

## Jest Testing
```javascript
import { createElement } from 'lwc';
import MyComponent from 'c/myComponent';
import getAccounts from '@salesforce/apex/AccountController.getAccounts';

jest.mock('@salesforce/apex/AccountController.getAccounts', () => ({
    default: jest.fn()
}), { virtual: true });

describe('c-my-component', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('displays accounts when data is returned', async () => {
        getAccounts.mockResolvedValue([{ Id: '001xx', Name: 'Test' }]);
        const element = createElement('c-my-component', { is: MyComponent });
        document.body.appendChild(element);

        await Promise.resolve(); // flush microtasks
        const items = element.shadowRoot.querySelectorAll('.account-item');
        expect(items.length).toBe(1);
    });
});
```
- Run with: `npx lwc-jest --coverage`
- Place tests in `__tests__/` subfolder within the component directory.
- Mock all `@salesforce/` imports (apex, schema, label, etc.).
- Use `Promise.resolve()` or `await flushPromises()` to wait for DOM updates.
- Clean up DOM in `afterEach` to avoid test pollution.
