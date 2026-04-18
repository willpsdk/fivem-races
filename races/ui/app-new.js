const overlay = document.getElementById('xmlOverlay');
const input = document.getElementById('xmlInput');
const importBtn = document.getElementById('importBtn');
const cancelBtn = document.getElementById('cancelBtn');

function post(name, payload = {}) {
  const payloadStr = JSON.stringify(payload);
  console.log('[RACE_BUILDER] Posting to:', name, 'payload length:', payloadStr.length);
  
  fetch(`https://${GetParentResourceName()}/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: payloadStr
  }).then(response => {
    console.log('[RACE_BUILDER] POST response status:', response.status);
    return response.json();
  }).catch((err) => {
    console.error('[RACE_BUILDER] Fetch error:', err);
  });
}

function openOverlay() {
  console.log('[RACE_BUILDER] Opening XML import overlay');
  overlay.classList.remove('hidden');
  input.value = '';
  input.focus();
  setTimeout(() => {
    input.focus();
    console.log('[RACE_BUILDER] Overlay opened and focused');
  }, 100);
}

function closeOverlay(sendCancel) {
  console.log('[RACE_BUILDER] Closing overlay, sendCancel:', sendCancel);
  overlay.classList.add('hidden');
  if (sendCancel) {
    post('racebuilderXmlCancel');
  }
}

// Listen for messages from Lua
window.addEventListener('message', (event) => {
  const data = event.data || {};
  if (data.action === 'openXmlPaste') {
    console.log('[RACE_BUILDER] Received openXmlPaste message');
    openOverlay();
  }
});

// Prevent clicking outside the panel
overlay.addEventListener('click', (event) => {
  if (event.target === overlay) {
    event.preventDefault();
    event.stopPropagation();
    event.stopImmediatePropagation();
    console.log('[RACE_BUILDER] Click outside panel blocked');
    return false;
  }
});

// import button
importBtn.addEventListener('click', () => {
  const xmlContent = input.value || '';
  console.log('[RACE_BUILDER] Import clicked - XML length:', xmlContent.length);
  post('racebuilderXmlImport', { xml: xmlContent });
  closeOverlay(false);
});

// Cancel button
cancelBtn.addEventListener('click', () => {
  console.log('[RACE_BUILDER] Cancel button clicked');
  closeOverlay(true);
});

// Handle all keyboard events - block everything except textarea input
document.addEventListener('keydown', (event) => {
  if (overlay.classList.contains('hidden')) {
    return;
  }

  const isTextareaFocused = document.activeElement === input;
  
  // Always allow typing in textarea
  if (isTextareaFocused) {
    // Allow all text input keys
    if (event.key.length === 1 || 
        event.key === 'Backspace' || 
        event.key === 'Delete' || 
        event.key === 'Tab' ||
        event.key === 'Enter' ||
        event.ctrlKey || 
        event.altKey || 
        event.shiftKey) {
      return; // Allow the key
    }
  }

  // ESC key should close the overlay
  if (event.key === 'Escape' || event.keyCode === 27) {
    console.log('[RACE_BUILDER] ESC key detected');
    event.preventDefault();
    event.stopPropagation();
    event.stopImmediatePropagation();
    closeOverlay(true);
    return false;
  }

  // Block ALL other keys
  event.preventDefault();
  event.stopPropagation();
  event.stopImmediatePropagation();
  return false;
}, true);

document.addEventListener('keyup', (event) => {
  if (overlay.classList.contains('hidden')) {
    return;
  }
  event.preventDefault();
  event.stopPropagation();
  event.stopImmediatePropagation();
  return false;
}, true);

document.addEventListener('keypress', (event) => {
  if (overlay.classList.contains('hidden')) {
    return;
  }
  const isTextareaFocused = document.activeElement === input;
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
