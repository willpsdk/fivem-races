// Checkpoint Display Configuration
const checkpointConfig = {
    scale: 1.0,            // Font scale multiplier (1.0 = normal size)
    fontSize: 30,          // Base font size in pixels
    offsetLeft: 886,         // pixels from left (positive = move right, negative = move left)
    offsetTop: 498,          // pixels from top (positive = move down, negative = move up)
    offsetRight: 0,        // pixels from right (use instead of offsetLeft for right positioning)
    offsetBottom: 0        // pixels from bottom (use instead of offsetTop for bottom positioning)
};

// Initialize container styles when page loads
window.addEventListener('load', function() {
    const container = document.getElementById('checkpoint-container');
    if (container) {
        applyCheckpointStyles(container);
    }
});

document.addEventListener('DOMContentLoaded', function() {
    const container = document.getElementById('checkpoint-container');
    if (container) {
        applyCheckpointStyles(container);
    }
});

function applyCheckpointStyles(container) {
    const text = document.getElementById('checkpoint-text');
    if (text) {
        text.style.fontSize = (checkpointConfig.fontSize * checkpointConfig.scale) + 'px';
    }
    
    // Apply position offsets
    if (checkpointConfig.offsetRight > 0) {
        container.style.right = checkpointConfig.offsetRight + 'px';
        container.style.left = 'auto';
    } else {
        container.style.left = (50 + (checkpointConfig.offsetLeft / window.innerWidth * 100)) + '%';
    }
    
    if (checkpointConfig.offsetBottom > 0) {
        container.style.bottom = checkpointConfig.offsetBottom + 'px';
        container.style.top = 'auto';
    } else {
        container.style.top = (50 + (checkpointConfig.offsetTop / window.innerHeight * 100)) + '%';
    }
    
    // Keep the transform for centering
    container.style.transform = 'translate(-50%, -50%)';
}

// NUI Message Handler for Checkpoint Display
window.addEventListener('message', (event) => {
    const data = event.data;
    
    if (data && data.type === 'checkpoint') {
        const container = document.getElementById('checkpoint-container');
        const text = document.getElementById('checkpoint-text');
        
        if (data.show) {
            text.textContent = data.display || '0 - 0';
            container.classList.remove('hidden');
        } else {
            container.classList.add('hidden');
        }
    }
});
