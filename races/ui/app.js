// Race Builder UI - Keyboard and Event Handling

// Get overlay element if it exists
const overlay = document.querySelector('[data-overlay="true"]') || document.createElement('div');

// Key down handler
document.addEventListener('keydown', (event) => {
  if (overlay.classList.contains('hidden')) {
    return;
  }
  
  const isTextareaFocused = document.activeElement === document.querySelector('input, textarea');
  
  if (event.key === 'Escape') {
    event.preventDefault();
    event.stopPropagation();
    event.stopImmediatePropagation();
    if (window.closeOverlay) {
      closeOverlay(true);
    }
    return false;
  }

  // Block ALL other keys
  if (!isTextareaFocused) {
    event.preventDefault();
    event.stopPropagation();
    event.stopImmediatePropagation();
    return false;
  }
}, true);

// Key up handler
document.addEventListener('keyup', (event) => {
  if (overlay.classList.contains('hidden')) {
    return;
  }
  event.preventDefault();
  event.stopPropagation();
  event.stopImmediatePropagation();
  return false;
}, true);

// Key press handler
document.addEventListener('keypress', (event) => {
  if (overlay.classList.contains('hidden')) {
    return;
  }
  const isTextareaFocused = document.activeElement === document.querySelector('input, textarea');
  if (!isTextareaFocused) {
    event.preventDefault();
    event.stopPropagation();
    event.stopImmediatePropagation();
    return false;
  }
}, true);

// Block context menu
document.addEventListener('contextmenu', (event) => {
  if (!overlay.classList.contains('hidden')) {
    event.preventDefault();
    event.stopPropagation();
  }
});

console.log('[RACE_BUILDER] app.js loaded successfully');
