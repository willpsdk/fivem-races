const overlay = document.getElementById('xmlOverlay');
const input = document.getElementById('xmlInput');
const importBtn = document.getElementById('importBtn');
const cancelBtn = document.getElementById('cancelBtn');

function post(name, payload = {}) {
  const payloadStr = JSON.stringify(payload);
  console.log('[RACE_BUILDER] Posting to:', name, 'payload length:', payloadStr.length);
  console.log('[RACE_BUILDER] First 200 chars:', payloadStr.substring(0, 200));
  
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
  console.log('[RACE_BUILDER] Opening overlay');
  overlay.classList.remove('hidden');
  input.value = '';
  setTimeout(() => {
    input.focus();
    input.click();
    console.log('[RACE_BUILDER] Overlay opened and focused');
  }, 50);
}

function closeOverlay(sendCancel) {
  console.log('[RACE_BUILDER] Closing overlay, sendCancel:', sendCancel);
  overlay.classList.add('hidden');
  if (sendCancel) {
    post('racebuilderXmlCancel');
  }
}

window.addEventListener('message', (event) => {
  const data = event.data || {};
  if (data.action) {
    console.log('[RACE_BUILDER] Message received:', data.action);
  }
  if (data.action === 'openXmlPaste') {
    openOverlay();
  }
});

importBtn.addEventListener('click', () => {
  const xmlContent = input.value || '';
  console.log('[RACE_BUILDER] Import clicked - XML length:', xmlContent.length);
  console.log('[RACE_BUILDER] XML starts with:', xmlContent.substring(0, 100));
  post('racebuilderXmlImport', { xml: xmlContent });
  closeOverlay(false);
});

cancelBtn.addEventListener('click', () => {
  console.log('[RACE_BUILDER] Cancel clicked');
  closeOverlay(true);
});

document.addEventListener('keydown', (event) => {
  if (overlay.classList.contains('hidden')) {
    return;
  }

  if (event.key === 'Escape' || event.keyCode === 27) {
    event.preventDefault();
    event.stopPropagation();
    event.stopImmediatePropagation();
    closeOverlay(true);
    return;
  }

  const isTextareaFocused = document.activeElement === input;
  if (!isTextareaFocused) {
    const key = event.key;
    if (key === 'ArrowUp' || key === 'ArrowDown' || key === 'ArrowLeft' || key === 'ArrowRight' ||
        key === 'Enter' || key === 'Tab' || key === 'Backspace' ||
        event.keyCode === 13 || event.keyCode === 9 || event.keyCode === 8) {
      event.preventDefault();
      event.stopPropagation();
      event.stopImmediatePropagation();
    }
  }
}, true);

document.addEventListener('keyup', (event) => {
  if (overlay.classList.contains('hidden')) {
    return;
  }
  event.stopPropagation();
  event.stopImmediatePropagation();
}, true);

console.log('[RACE_BUILDER] app.js loaded successfully');
