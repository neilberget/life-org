# Troubleshooting

## Quill.js Editor Disappearing After Navigation

**Problem:** The Quill.js rich text editor in the journal form (on `/` page) would sometimes revert to a plain textarea after tabbing away and returning, or after navigation/LiveView updates.

**Root Cause:** The `RichTextEditor` hook (`assets/js/hooks/rich_text_editor.js`) only had a `mounted()` lifecycle callback. When Phoenix LiveView patches the DOM (during navigation, updates, or page re-renders), the Quill instance gets destroyed but never re-initialized, leaving only the raw HTML elements visible.

**Solution:** Added two enhancements to the hook:

1. **`updated()` lifecycle hook** - Called whenever LiveView updates the DOM. Checks if Quill needs re-initialization by detecting:
   - Missing `this.quill` instance
   - Missing editor container element
   - Missing Quill's `.ql-container` CSS class

2. **`initializeEditor()` method** - Refactored all initialization logic into a reusable method that can be called from both `mounted()` and `updated()`. Includes guards to prevent double-initialization.

**Files Changed:**
- `assets/js/hooks/rich_text_editor.js`

**Key Code Pattern:**
```javascript
mounted() {
    this.initializeEditor();
},

updated() {
    const editorContainer = this.el.querySelector('.rich-text-content');
    if (!this.quill || !editorContainer || !editorContainer.classList.contains('ql-container')) {
        this.initializeEditor();
    }
},

initializeEditor() {
    // Prevent double initialization
    if (this.quill && this.el.querySelector('.ql-container')) {
        return;
    }
    // ... rest of initialization
}
```

**General Pattern:** Phoenix LiveView hooks should implement both `mounted()` and `updated()` lifecycle callbacks when integrating third-party JavaScript libraries that manipulate the DOM. Always check if re-initialization is needed in `updated()` to handle DOM patches.

_Added: 2025-10-27_
