/**
 * TalkdeskNotesParser — Parses structured call notes from talkdesk__Notes__c.
 *
 * Expected format:
 *   **Header:** Value text here
 *   **Another Header:** Another value
 *   - Bullet items (ignored)
 *
 * Extracts values between **Header:** markers. Ignores content after the last
 * recognized header section (action item bullets, etc.).
 */
public with sharing class TalkdeskNotesParser {

    // Header labels that map to qualification fields
    private static final Map<String, String> HEADER_TO_FIELD = new Map<String, String>{
        'Customer Story' => 'Customer_Story__c',
        'Inception or Switcher' => 'Inception_Or_Switcher__c',
        'Decision Maker Identified' => 'Decision_Maker_Identified__c',
        'Business Challenges' => 'Business_Challenges__c',
        'Best Product Fit Identified' => 'Best_Product_Fit_Identified__c',
        'Features and Benefits Discussed' => 'Features_Benefits_Discussed__c',
        'Budget Confirmed' => 'Budget_Confirmed__c',
        'Timeline Confirmed' => 'Timeline_Confirmed__c',
        'Verbal Commit' => 'Verbal_Commit__c'
    };

    private static final Set<String> BOOLEAN_FIELDS = new Set<String>{
        'Decision_Maker_Identified__c',
        'Best_Product_Fit_Identified__c',
        'Budget_Confirmed__c',
        'Timeline_Confirmed__c',
        'Verbal_Commit__c'
    };

    /**
     * Parse talkdesk__Notes__c text and return a map of field API name → value (String).
     * Boolean fields are returned as 'true'/'false' strings for the caller to convert.
     */
    public static Map<String, String> parse(String notesText) {
        Map<String, String> result = new Map<String, String>();
        if (String.isBlank(notesText)) {
            return result;
        }

        // Split into lines
        List<String> lines = notesText.split('\n');

        String currentField = null;
        String currentValue = '';

        for (String line : lines) {
            String trimmed = line.trim();

            // Check if this line starts a new header: **Header:** value
            String headerMatch = matchHeader(trimmed);
            if (headerMatch != null) {
                // Save previous field if we had one
                if (currentField != null) {
                    result.put(currentField, currentValue.trim());
                }

                // Extract the field name and the value portion after the colon
                String fieldName = HEADER_TO_FIELD.get(headerMatch);
                currentField = fieldName;
                // Get everything after "**Header:**"
                String afterHeader = trimmed.substringAfter('**' + headerMatch + ':**');
                if (afterHeader == null) {
                    // Try alternate format: **Header: ** (space before closing **)
                    afterHeader = '';
                }
                currentValue = afterHeader.trim();
            } else if (currentField != null) {
                // Continuation line — only append if it's not a bullet point starting a new section
                if (trimmed.startsWith('- ') && !isKnownHeaderAhead(lines, lines.indexOf(line))) {
                    // This looks like action items at the end — stop parsing
                    break;
                }
                if (String.isNotBlank(trimmed)) {
                    currentValue += ' ' + trimmed;
                }
            }
        }

        // Save the last field
        if (currentField != null) {
            result.put(currentField, currentValue.trim());
        }

        return result;
    }

    /**
     * Apply parsed values to a Talkdesk Activity record (used in BEFORE INSERT).
     */
    public static void applyToRecord(talkdesk__Talkdesk_Activity__c record, Map<String, String> parsed) {
        if (parsed == null || parsed.isEmpty()) {
            return;
        }

        for (String fieldName : parsed.keySet()) {
            String value = parsed.get(fieldName);
            if (String.isBlank(value)) {
                continue;
            }

            if (BOOLEAN_FIELDS.contains(fieldName)) {
                record.put(fieldName, toBool(value));
            } else {
                record.put(fieldName, value);
            }
        }
    }

    /**
     * Check if a line matches a known **Header:** pattern.
     * Returns the header label if matched, null otherwise.
     */
    @TestVisible
    static String matchHeader(String line) {
        if (!line.startsWith('**') || !line.contains(':**')) {
            return null;
        }

        for (String header : HEADER_TO_FIELD.keySet()) {
            if (line.startsWith('**' + header + ':**')) {
                return header;
            }
        }
        return null;
    }

    /**
     * Convert string to boolean. Handles 'True'/'False' (case-insensitive).
     */
    private static Boolean toBool(String value) {
        return value != null && value.trim().equalsIgnoreCase('true');
    }

    /**
     * Lookahead: check if there are any more known headers after the current line index.
     * Used to distinguish action-item bullets from mid-section content.
     */
    private static Boolean isKnownHeaderAhead(List<String> lines, Integer currentIndex) {
        for (Integer i = currentIndex + 1; i < lines.size(); i++) {
            if (matchHeader(lines[i].trim()) != null) {
                return true;
            }
        }
        return false;
    }
}
