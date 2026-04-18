// Countdown Configuration
const countdownConfig = {
    positionTop: 30,      // Percentage from top of screen (0-100)
    positionLeft: 50,     // Percentage from left of screen (0-100)
    width: 1280,           // Width in pixels
    height: 720,          // Height in pixels
    animationDuration: 300 // Animation duration in milliseconds
};

// Initialize container styles when page loads
window.addEventListener('load', function() {
    const container = document.getElementById('countdown-container');
    if (container) {
        container.style.top = countdownConfig.positionTop + '%';
        container.style.left = countdownConfig.positionLeft + '%';
        container.style.width = countdownConfig.width + 'px';
        container.style.height = countdownConfig.height + 'px';
    }
});

// Also initialize immediately in case load fires before this script
document.addEventListener('DOMContentLoaded', function() {
    const container = document.getElementById('countdown-container');
    if (container) {
        container.style.top = countdownConfig.positionTop + '%';
        container.style.left = countdownConfig.positionLeft + '%';
        container.style.width = countdownConfig.width + 'px';
        container.style.height = countdownConfig.height + 'px';
    }
});

window.addEventListener('message', (event) => {
    const data = event.data;
    
    if (data && data.type === 'countdown') {
        const container = document.getElementById('countdown-container');
        const image = document.getElementById('countdown-image');
        
        console.log('Countdown event:', data);
        
        if (data.show) {
            const imagePath = `images/${data.number}.png`;
            console.log('Loading image:', imagePath);
            image.src = imagePath;
            
            // Remove fadeOut class for regular countdown numbers
            if (data.number !== 'Go') {
                image.classList.remove('fadeOut');
            }
            
            image.onerror = function() {
                console.error('Failed to load image:', imagePath);
            };
            image.onload = function() {
                console.log('Image loaded successfully:', imagePath);
                // Add fadeOut animation for GO
                if (data.number === 'Go') {
                    image.classList.add('fadeOut');
                }
            };
            container.classList.remove('hidden');
            console.log('Countdown shown');
        } else {
            container.classList.add('hidden');
            console.log('Countdown hidden');
        }
    }
});
