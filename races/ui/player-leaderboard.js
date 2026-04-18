const playerLeaderboardConfig = {
    fontSize: 30,
    offsetLeft: 1650,      // pixels from left
    offsetTop: 828,        // pixels from top (player-1 starts here)
    offsetRight: 0,        // pixels from right (if > 0, overrides offsetLeft)
    lineSpacing: 46.5      // pixels between player entries
};

window.addEventListener('DOMContentLoaded', () => {
    applyPlayerLeaderboardPositioning();
});

window.addEventListener('load', () => {
    applyPlayerLeaderboardPositioning();
});

function applyPlayerLeaderboardPositioning() {
    for (let i = 1; i <= 4; i++) {
        const playerEntry = document.getElementById('player-' + i);
        if (playerEntry) {
            const playerNameEl = playerEntry.querySelector('.player-name');
            if (playerNameEl) {
                playerNameEl.style.fontSize = playerLeaderboardConfig.fontSize + 'px';
            }
            
            let top, left;
            
            // Position from top down (player-1 at top, player-4 at bottom)
            top = playerLeaderboardConfig.offsetTop + (i - 1) * playerLeaderboardConfig.lineSpacing + 'px';
            
            if (playerLeaderboardConfig.offsetRight > 0) {
                left = `calc(100vw - ${playerLeaderboardConfig.offsetRight}px)`;
            } else {
                left = playerLeaderboardConfig.offsetLeft + 'px';
            }
            
            playerEntry.style.top = top;
            playerEntry.style.left = left;
        }
    }
}

window.addEventListener('message', (event) => {
    const data = event.data;
    
    if (data && data.type === 'player-leaderboard') {
        const container = document.getElementById('player-leaderboard-container');
        
        if (data.show) {
            for (let i = 1; i <= 4; i++) {
                const playerEntry = document.getElementById('player-' + i);
                if (playerEntry) {
                    const playerNameEl = playerEntry.querySelector('.player-name');
                    const playerData = data.players && data.players[i - 1];
                    
                    if (playerData) {
                        playerNameEl.textContent = playerData.name || 'Placeholder';
                        playerEntry.style.display = 'flex';
                    } else {
                        playerEntry.style.display = 'none';
                    }
                }
            }
            
            container.classList.remove('hidden');
        } else {
            container.classList.add('hidden');
        }
    }
});
