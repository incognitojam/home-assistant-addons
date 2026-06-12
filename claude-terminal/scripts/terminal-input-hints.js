(() => {
    const selector = [
        'textarea.xterm-helper-textarea',
        '.xterm textarea',
        '.xterm input[type="text"]',
        '.xterm input:not([type])',
    ].join(',');

    const hints = {
        autocomplete: 'off',
        autocorrect: 'off',
        autocapitalize: 'off',
        spellcheck: 'false',
    };

    const applyHints = element => {
        if (!(element instanceof HTMLInputElement || element instanceof HTMLTextAreaElement)) return;
        if (!element.closest('.xterm')) return;

        for (const [name, value] of Object.entries(hints)) {
            element.setAttribute(name, value);
        }
        element.spellcheck = false;
    };

    const applyHintsFrom = root => {
        if (root instanceof Element && root.matches(selector)) {
            applyHints(root);
        }
        if (typeof root.querySelectorAll === 'function') {
            root.querySelectorAll(selector).forEach(applyHints);
        }
    };

    const start = () => {
        applyHintsFrom(document);
        document.addEventListener('focusin', event => applyHints(event.target), true);

        const observer = new MutationObserver(mutations => {
            for (const mutation of mutations) {
                mutation.addedNodes.forEach(applyHintsFrom);
            }
        });
        observer.observe(document.documentElement, { childList: true, subtree: true });
    };

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', start, { once: true });
    } else {
        start();
    }
})();
