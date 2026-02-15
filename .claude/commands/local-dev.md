Help me set up and use Salesforce Local Dev for LWC hot-reload preview.

## Step 1: Check prerequisites
Verify the setup:
1. Run `sf org list` to confirm a connected org
2. Remind user to check: Setup > User Interface > "Enable Local Development" must be ON in the org
3. Check that Node.js is installed: `node --version` (requires Node 18+)

## Step 2: Start local dev server

**Preview full app (all LWC components):**
```
sf lightning dev app
```

**Preview a specific component:**
```
sf lightning dev component --name componentName
```

Default URL: `http://localhost:3333`

## Step 3: Explain hot reload behavior

Tell the user:
- **Hot reload works for:** HTML template changes, CSS style changes, JS logic changes
- **Requires redeployment for:** New `@api` properties, `@wire` adapter changes, `.js-meta.xml` target changes, new component creation
- **Workflow:** Edit files locally → see changes instantly in browser → when done, deploy to org

## Troubleshooting

If the user has issues, check these common problems:

**Port conflict (address already in use):**
```
sf lightning dev app --port 3334
```

**Lightning Web Security not enabled:**
- Go to Setup > Session Settings > enable "Use Lightning Web Security for Lightning web components"

**Org not enabled for Local Dev:**
- Go to Setup > User Interface > enable "Enable Local Development"

**Component not showing:**
- Ensure the component has `isExposed: true` in the meta XML
- Ensure the component has the correct `<targets>` for the page type being previewed

**Authentication error:**
- Re-authenticate: `sf org login web --set-default --alias myorg`

Always explain issues in plain language and provide the fix.
