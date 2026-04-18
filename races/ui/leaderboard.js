// Leaderboard Configuration
const leaderboardConfig = {
    offsetLeft: 150.0,      // pixels to move left (negative = move right)
    offsetTop: 85.0,       // pixels to move up (negative = move down)
    offsetRight: 0,     // pixels from right edge (0 = no offset)
    offsetBottom: 0     // pixels from bottom edge (0 = no offset)
};

// Initialize on page load
document.addEventListener('DOMContentLoaded', function() {
    applyLeaderboardPosition();
});

window.addEventListener('load', function() {
    applyLeaderboardPosition();
});

function applyLeaderboardPosition() {
    const container = document.getElementById('leaderboard-container');
    if (container) {
        // Center the image by default
        let left = 'calc(50% - 960px)';  // Half of viewport - half of image width
        let top = 'calc(50% - 540px)';   // Half of viewport - half of image height
        
        // Apply offsets
        if (leaderboardConfig.offsetLeft !== 0) {
            left = 'calc(50% - 960px + ' + leaderboardConfig.offsetLeft + 'px)';
        }
        if (leaderboardConfig.offsetTop !== 0) {
            top = 'calc(50% - 540px + ' + leaderboardConfig.offsetTop + 'px)';
        }
        
        container.style.left = left;
        container.style.top = top;
    }
}

window.addEventListener('message', (event) => {
    const data = event.data;
    
    if (data && data.type === 'leaderboard') {
        const container = document.getElementById('leaderboard-container');
        
        if (data.show) {
            container.classList.remove('hidden');
        } else {
            container.classList.add('hidden');
        }
    }
});
