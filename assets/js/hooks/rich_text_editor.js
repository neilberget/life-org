import Quill from 'quill';
import TurndownService from 'turndown';

let RichTextEditor = {
    mounted() {
        // Initialize turndown service for HTML to Markdown conversion
        this.turndownService = new TurndownService({
            codeBlockStyle: 'fenced',
            headingStyle: 'atx',
            emDelimiter: '*',
            strongDelimiter: '**',
            linkStyle: 'inlined'
        });

        // Add custom rule for checkboxes to preserve todo syntax
        this.turndownService.addRule('taskList', {
            filter: function (node) {
                return node.type === 'checkbox' ||
                    (node.nodeName === 'INPUT' && node.type === 'checkbox');
            },
            replacement: function (content, node) {
                return node.checked ? '[x]' : '[ ]';
            }
        });

        // Handle list items with checkboxes
        this.turndownService.addRule('taskListItem', {
            filter: function (node) {
                return (node.nodeName === 'LI' || node.nodeName === 'P') &&
                    node.querySelector('input[type="checkbox"]');
            },
            replacement: function (content, node) {
                const checkbox = node.querySelector('input[type="checkbox"]');
                const isChecked = checkbox && checkbox.checked;
                const text = content.replace(/^\s*\[.\]\s*/, ''); // Remove any existing checkbox syntax
                return (isChecked ? '[x]' : '[ ]') + ' ' + text + '\n';
            }
        });

        // Configure Quill toolbar
        const toolbarOptions = [
            ['bold', 'italic', 'underline', 'strike'],
            ['blockquote', 'code-block'],
            [{ 'header': 1 }, { 'header': 2 }],
            [{ 'list': 'ordered' }, { 'list': 'bullet' }],
            [{ 'script': 'sub' }, { 'script': 'super' }],
            ['link'],
            ['clean']
        ];

        // Initialize Quill editor
        this.quill = new Quill(this.el.querySelector('.rich-text-content'), {
            theme: 'snow',
            modules: {
                toolbar: toolbarOptions,
                // Disable keyboard shortcuts that interfere with checkbox syntax
                keyboard: {
                    bindings: {
                        // Disable auto-list creation completely
                        'list autofill': {
                            key: ' ',
                            collapsed: true,
                            format: ['list'],
                            prefix: /^(1\.|-)$/,
                            handler: function () {
                                // Do nothing - disable auto-list creation
                                return true;
                            }
                        },
                        // Disable numbered list autoformatting that converts [] to 1.
                        'code exit': false,
                        'embed left': false,
                        'embed right': false,
                        // Keep useful shortcuts
                        'indent': {
                            key: 'Tab'
                        },
                        'outdent': {
                            key: 'Tab',
                            shiftKey: true
                        }
                    }
                }
            },
            placeholder: this.el.dataset.placeholder || 'Write something...'
        });

        // Set initial content if provided
        const initialContent = this.el.dataset.initialContent;
        if (initialContent && initialContent.trim() !== '') {
            // Convert markdown to HTML for Quill display
            this.quill.root.innerHTML = this.markdownToHtml(initialContent);
        }

        // Handle content changes with debouncing
        let timeout;
        this.quill.on('text-change', () => {
            clearTimeout(timeout);
            timeout = setTimeout(() => {
                this.pushContentUpdate();
            }, 500); // 500ms debounce
        });

        // Handle form submission
        this.handleEvent('form_submit', () => {
            this.pushContentUpdate();
        });

        // Handle form reset
        this.handleEvent('clear_form', () => {
            this.quill.setContents([]);
        });

        // Handle external content updates
        this.handleEvent('content_update', ({ content }) => {
            const currentContent = this.getMarkdownContent();
            if (content !== currentContent) {
                this.quill.root.innerHTML = this.markdownToHtml(content);
            }
        });

        // Handle validation errors
        this.handleEvent('validation_error', ({ errors }) => {
            const errorDiv = this.el.querySelector('.rich-text-errors');
            if (errorDiv) {
                if (errors && errors.length > 0) {
                    errorDiv.innerHTML = errors.map(error => `<span class="text-red-500 text-sm">${error}</span>`).join('<br>');
                    errorDiv.style.display = 'block';
                } else {
                    errorDiv.style.display = 'none';
                }
            }
        });


    },

    pushContentUpdate() {
        const content = this.getMarkdownContent();
        const fieldName = this.el.dataset.field;

        // Update the hidden input field for form submission
        const hiddenInput = this.el.querySelector('input[type="hidden"]');
        if (hiddenInput) {
            hiddenInput.value = content;
        }

        // Optional: Send event to LiveView for real-time updates
        // Commented out to prevent crashes - uncomment if needed for real-time features
        // this.pushEvent('rich_text_change', {
        //   field: fieldName,
        //   content: content,
        //   text: this.quill.getText()
        // });
    },

    getMarkdownContent() {
        const html = this.quill.root.innerHTML;
        // Convert HTML to Markdown
        let markdown = this.turndownService.turndown(html);

        // Clean up any escaped characters that might interfere with checkbox syntax
        markdown = markdown
            .replace(/\\(\[|\])/g, '$1')  // Remove escaping from brackets
            .replace(/\\\-/g, '-')        // Remove escaping from dashes
            .replace(/\n\n+/g, '\n\n')    // Normalize multiple newlines
            .replace(/\[\]/g, '[ ]')  // Ensure space in empty checkboxes
            .replace(/\[x\]/gi, '[x]') // Ensure proper checked checkbox format
            .replace(/(\d+)\.\s*\[ \]/g, '[ ]') // Convert numbered list checkboxes to simple checkboxes
            .replace(/(\d+)\.\s*\[x\]/gi, '[x]') // Convert numbered list checked checkboxes to simple checkboxes
            .replace(/(\d+)\.\s*- \[ \]/g, '[ ]') // Convert numbered list bullet checkboxes to simple checkboxes
            .replace(/(\d+)\.\s*- \[x\]/gi, '[x]') // Convert numbered list bullet checked checkboxes to simple checkboxes
            .trim();

        return markdown;
    },

    markdownToHtml(markdown) {
        if (!markdown || markdown.trim() === '') {
            return '<p><br></p>';
        }

        // Split into lines for better processing
        let lines = markdown.split('\n');
        let html = '';
        let inList = false;

        for (let line of lines) {
            const trimmed = line.trim();

            // Handle headers
            if (trimmed.startsWith('# ')) {
                html += '<h1>' + trimmed.slice(2) + '</h1>';
            } else if (trimmed.startsWith('## ')) {
                html += '<h2>' + trimmed.slice(3) + '</h2>';
            }
            // Handle todo checkboxes (with or without dashes)
            else if (trimmed.match(/^- \[ \]/) || trimmed.match(/^\[ \]/)) {
                if (inList) { html += '</ul>'; inList = false; }
                const text = trimmed.replace(/^(-\s*)?\[\s*\]\s*/, '');
                html += '<p><input type="checkbox"> ' + this.processInlineMarkdown(text) + '</p>';
            } else if (trimmed.match(/^- \[x\]/i) || trimmed.match(/^\[x\]/i)) {
                if (inList) { html += '</ul>'; inList = false; }
                const text = trimmed.replace(/^(-\s*)?\[x\]\s*/i, '');
                html += '<p><input type="checkbox" checked> ' + this.processInlineMarkdown(text) + '</p>';
            }
            // Handle regular bullets
            else if (trimmed.startsWith('- ')) {
                if (!inList) {
                    html += '<ul>';
                    inList = true;
                }
                const text = trimmed.slice(2);
                html += '<li>' + this.processInlineMarkdown(text) + '</li>';
            }
            // Handle numbered lists
            else if (trimmed.match(/^\d+\. /)) {
                if (!inList) {
                    html += '<ol>';
                    inList = true;
                }
                const text = trimmed.replace(/^\d+\.\s*/, '');
                html += '<li>' + this.processInlineMarkdown(text) + '</li>';
            }
            // Handle regular content
            else {
                if (inList) {
                    html += '</ul>';
                    inList = false;
                }
                if (trimmed === '') {
                    // Skip empty lines - they'll be handled by paragraph spacing
                    continue;
                } else {
                    html += '<p>' + this.processInlineMarkdown(trimmed) + '</p>';
                }
            }
        }

        // Close any open list
        if (inList) {
            html += '</ul>';
        }

        return html || '<p><br></p>';
    },

    processInlineMarkdown(text) {
        return text
            .replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>')
            .replace(/\*(.*?)\*/g, '<em>$1</em>')
            .replace(/`(.*?)`/g, '<code>$1</code>');
    },

    destroyed() {
        if (this.quill) {
            this.quill = null;
        }
    }
};

export default RichTextEditor;
