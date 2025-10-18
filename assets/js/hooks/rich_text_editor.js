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

        // Handle paragraphs with checkboxes (our checkbox format)
        this.turndownService.addRule('checkboxParagraph', {
            filter: function (node) {
                const hasCheckbox = node.nodeName === 'P' && node.querySelector('input[type="checkbox"]');
                if (hasCheckbox) {
                    console.log("Found paragraph with checkbox:", node.outerHTML);
                }
                return hasCheckbox;
            },
            replacement: function (content, node) {
                console.log("Converting checkbox paragraph:", node.outerHTML, "content:", content);
                
                const checkbox = node.querySelector('input[type="checkbox"]');
                const isChecked = checkbox && checkbox.checked;
                
                // Extract just the text content, removing any checkbox HTML
                const textNodes = [];
                for (let child of node.childNodes) {
                    if (child.nodeType === Node.TEXT_NODE) {
                        textNodes.push(child.textContent);
                    } else if (child.nodeName !== 'INPUT') {
                        textNodes.push(child.textContent);
                    }
                }
                const text = textNodes.join('').trim();
                
                const result = '- ' + (isChecked ? '[x]' : '[ ]') + ' ' + text + '\n\n';
                console.log("Checkbox conversion result:", result);
                return result;
            }
        });

        // Handle list items with checkboxes (fallback)
        this.turndownService.addRule('checkboxListItem', {
            filter: function (node) {
                return node.nodeName === 'LI' && node.querySelector('input[type="checkbox"]');
            },
            replacement: function (content, node) {
                const checkbox = node.querySelector('input[type="checkbox"]');
                const isChecked = checkbox && checkbox.checked;
                const text = content.replace(/^\s*/, '').trim();
                return '- ' + (isChecked ? '[x]' : '[ ]') + ' ' + text + '\n';
            }
        });

        // Configure Quill toolbar with image support
        const toolbarOptions = [
            ['bold', 'italic', 'underline', 'strike'],
            ['blockquote', 'code-block'],
            [{ 'header': 1 }, { 'header': 2 }],
            [{ 'list': 'ordered' }, { 'list': 'bullet' }],
            [{ 'script': 'sub' }, { 'script': 'super' }],
            ['link', 'image'],
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

        // Prevent Quill from handling images automatically
        // This stops base64 conversion and forces our upload flow
        this.quill.root.addEventListener('drop', (e) => {
            // Check if dropped files contain images
            if (e.dataTransfer.files && e.dataTransfer.files.length > 0) {
                const imageFiles = Array.from(e.dataTransfer.files).filter(file => file.type.startsWith('image/'));
                if (imageFiles.length > 0) {
                    e.preventDefault();
                    e.stopPropagation();
                    console.log('Intercepted image drop, uploading...');
                    this.uploadImages(imageFiles);
                    return false;
                }
            }
        }, true); // Use capture phase to intercept before Quill

        this.quill.root.addEventListener('paste', (e) => {
            // Check if pasted content contains images
            if (e.clipboardData && e.clipboardData.files && e.clipboardData.files.length > 0) {
                const imageFiles = Array.from(e.clipboardData.files).filter(file => file.type.startsWith('image/'));
                if (imageFiles.length > 0) {
                    e.preventDefault();
                    e.stopPropagation();
                    this.uploadImages(imageFiles);
                    return false;
                }
            }
        }, true); // Use capture phase

        // Set initial content if provided
        const initialContent = this.el.dataset.initialContent;
        if (initialContent && initialContent.trim() !== '') {
            // Convert markdown to HTML for Quill display
            this.quill.root.innerHTML = this.markdownToHtml(initialContent);
        }

        // Setup image upload handler
        this.setupImageHandler();

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
        console.log("Converting HTML to markdown:", html);

        // Convert HTML to Markdown
        let markdown = this.turndownService.turndown(html);
        console.log("Initial markdown:", markdown);

        // Clean up any escaped characters that might interfere with checkbox syntax or images
        markdown = markdown
            .replace(/\\(\[|\])/g, '$1')  // Remove escaping from brackets
            .replace(/\\\!/g, '!')        // Remove escaping from exclamation marks (important for images)
            .replace(/\\\-/g, '-')        // Remove escaping from dashes
            .replace(/\n\n+/g, '\n\n')    // Normalize multiple newlines
            .replace(/\[\]/g, '[ ]')  // Ensure space in empty checkboxes
            .replace(/\[x\]/gi, '[x]') // Ensure proper checked checkbox format
            .replace(/(\d+)\.\s*\[ \]/g, '- [ ]') // Convert numbered list checkboxes to simple checkboxes
            .replace(/(\d+)\.\s*\[x\]/gi, '- [x]') // Convert numbered list checked checkboxes to simple checkboxes
            .replace(/(\d+)\.\s*- \[ \]/g, '- [ ]') // Convert numbered list bullet checkboxes to simple checkboxes
            .replace(/(\d+)\.\s*- \[x\]/gi, '- [x]') // Convert numbered list bullet checked checkboxes to simple checkboxes
            .trim();

        console.log("Final markdown:", markdown);
        return markdown;
    },

    markdownToHtml(markdown) {
        if (!markdown || markdown.trim() === '') {
            return '<p><br></p>';
        }

        console.log("Converting markdown to HTML:", markdown);

        // Split into lines for better processing
        let lines = markdown.split('\n');
        let html = '';
        let inList = false;

        for (let line of lines) {
            const trimmed = line.trim();
            console.log("Processing line:", trimmed);

            // Handle headers
            if (trimmed.startsWith('# ')) {
                html += '<h1>' + trimmed.slice(2) + '</h1>';
            } else if (trimmed.startsWith('## ')) {
                html += '<h2>' + trimmed.slice(3) + '</h2>';
            }
            // Handle todo checkboxes (with or without dashes)
            else if (trimmed.match(/^-\s*\[\s*\]/) || trimmed.match(/^\[\s*\]/)) {
                if (inList) { html += '</ul>'; inList = false; }
                const text = trimmed.replace(/^(-\s*)?\[\s*\]\s*/, '');
                html += '<p><input type="checkbox"> ' + this.processInlineMarkdown(text) + '</p>';
            } else if (trimmed.match(/^-\s*\[x\]/i) || trimmed.match(/^\[x\]/i)) {
                if (inList) { html += '</ul>'; inList = false; }
                const text = trimmed.replace(/^(-\s*)?\[x\]\s*/i, '');
                html += '<p><input type="checkbox" checked> ' + this.processInlineMarkdown(text) + '</p>';
            }
            // Handle brackets that are NOT checkboxes (like [TEST]) - preserve as literal text
            else if (trimmed.match(/^- \[[^\]]*\]/)) {
                if (inList) { html += '</ul>'; inList = false; }
                html += '<p>' + this.processInlineMarkdown(trimmed) + '</p>';
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
            // Handle images
            else if (trimmed.match(/^!\[([^\]]*)\]\(([^\)]+)\)/)) {
                if (inList) { html += '</ul>'; inList = false; }
                const match = trimmed.match(/^!\[([^\]]*)\]\(([^\)]+)\)/);
                const alt = match[1] || 'image';
                const src = match[2];
                html += `<img src="${src}" alt="${alt}" style="max-width: 100%;" />`;
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

    setupImageHandler() {
        const toolbar = this.quill.getModule('toolbar');
        toolbar.addHandler('image', () => {
            this.selectLocalImage();
        });

        // Listen for images_uploaded event from LiveView
        this.handleEvent('images_uploaded', ({ files }) => {
            console.log('Received images_uploaded event with files:', files);
            files.forEach(file => {
                console.log('Inserting image markdown for:', file.url);
                this.insertImageMarkdown(file.url);
            });
        });
    },

    selectLocalImage() {
        const input = document.createElement('input');
        input.setAttribute('type', 'file');
        input.setAttribute('accept', 'image/jpeg,image/jpg,image/png,image/gif,image/webp');
        input.setAttribute('multiple', 'multiple');
        input.click();

        input.onchange = () => {
            const files = Array.from(input.files);
            if (files && files.length > 0) {
                this.uploadImages(files);
            }
        };
    },

    setupDragAndDrop() {
        const editor = this.quill.root;

        // Prevent default drag behaviors
        ['dragenter', 'dragover', 'dragleave', 'drop'].forEach(eventName => {
            editor.addEventListener(eventName, (e) => {
                e.preventDefault();
                e.stopPropagation();
            }, false);
        });

        // Highlight drop area when item is dragged over it
        ['dragenter', 'dragover'].forEach(eventName => {
            editor.addEventListener(eventName, () => {
                editor.classList.add('drag-over');
            }, false);
        });

        ['dragleave', 'drop'].forEach(eventName => {
            editor.addEventListener(eventName, () => {
                editor.classList.remove('drag-over');
            }, false);
        });

        // Handle dropped files
        editor.addEventListener('drop', (e) => {
            const dt = e.dataTransfer;
            const files = Array.from(dt.files).filter(file => file.type.startsWith('image/'));

            if (files.length > 0) {
                this.uploadImages(files);
            }
        }, false);
    },

    uploadImages(files) {
        console.log('Uploading files:', files);

        // Upload each file
        files.forEach((file, index) => {
            const reader = new FileReader();

            reader.onload = (e) => {
                const base64Data = e.target.result;
                console.log(`File ${index} loaded, size: ${base64Data.length} bytes`);

                // Send the file data to LiveView
                this.pushEvent('upload_image_base64', {
                    filename: file.name,
                    content_type: file.type,
                    size: file.size,
                    data: base64Data
                });
            };

            reader.onerror = (error) => {
                console.error('Error reading file:', error);
            };

            reader.readAsDataURL(file);
        });
    },

    insertImageMarkdown(url) {
        // Get current cursor position
        const range = this.quill.getSelection(true);
        const position = range ? range.index : this.quill.getLength();

        // Insert markdown image syntax at cursor position
        const markdown = `![image](${url})`;
        this.quill.insertText(position, markdown + '\n');

        // Move cursor after inserted text
        this.quill.setSelection(position + markdown.length + 1);

        // Trigger content update
        this.pushContentUpdate();
    },

    destroyed() {
        if (this.quill) {
            this.quill = null;
        }
    }
};

export default RichTextEditor;
