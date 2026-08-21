// ==UserScript==
// @name         20 Burning Hot – 0.40 RON (Chrome PC)
// @namespace    .
// @version      4.1
// @description  Auto-bet 0.40 RON | 20 Burning Hot | Chrome Desktop
// @author       Grok
// @match        *superbet.ro/*
// @match        *superbet.ro/joc/*burning*
// @match        */casino/*
// @match        */slots/*
// @grant        none
// ==/UserScript==

(function() {
    'use strict';

    // =============== SETĂRI ===============
    const FIXED_BET     = 0.40;
    const GAMBLE_MAX    = 2.00;
    const GAMBLE_CHANCE = 0.65;
    const INTERVAL      = 700;
    const STOP_PROFIT   = 60;
    const STOP_LOSS     = -40;
    // ======================================

    let isRunning = false;
    let overlay = null;
    let spinCount = 0;
    let startBalance = null;
    let profit = 0;
    let showOverlay = true;
    let lastAction = '';

    const sel = {
        spin:    'button.spin, [data-action="spin"], .spin-button, button[aria-label*="spin" i]',
        bet:     'input.bet-amount, input[type="number"], input[data-bet]',
        balance: '.balance, .user-balance, [data-balance], .amount, .RON, .wallet-amount',
        gamble:  'button.gamble, [data-action="gamble"], button:contains("Gamble")',
        collect: 'button.collect, [data-action="collect"], button:contains("Collect")',
        feature: '.feature-container, .bonus-feature, .free-spins, [class*="bonus"], [class*="feature"]'
    };

    function $(s) { return document.querySelector(s); }

    function getBalance() {
        const el = $(sel.balance);
        if (!el) return null;
        return parseFloat(el.textContent.replace(/[^0-9.,-]/g, '').replace(',', '.')) || null;
    }

    function createOverlay() {
        if (overlay) return;
        overlay = document.createElement('div');
        Object.assign(overlay.style, {
            position: 'fixed',
            bottom: '15px',
            right: '15px',
            zIndex: '999999',
            background: 'rgba(0,0,0,0.88)',
            color: '#0f0',
            padding: '10px 14px',
            borderRadius: '8px',
            font: '13px Consolas, monospace',
            lineHeight: '1.45',
            border: '1px solid #0a0',
            minWidth: '160px',
            pointerEvents: 'none'
        });
        document.body.appendChild(overlay);
    }

    function updateOverlay(msg = '') {
        createOverlay();
        const bal = getBalance();
        if (bal !== null) {
            if (startBalance === null) startBalance = bal;
            profit = +(bal - startBalance).toFixed(2);
        }

        if (isRunning) {
            if (STOP_PROFIT > 0 && profit >= STOP_PROFIT) {
                isRunning = false;
                msg = 'STOP PROFIT';
            }
            if (STOP_LOSS < 0 && profit <= STOP_LOSS) {
                isRunning = false;
                msg = 'STOP LOSS';
            }
        }

        const status = isRunning ? '▶ RUNNING' : '⏹ STOPPED';
        const col = profit >= 0 ? '#0f0' : '#f55';

        overlay.innerHTML = `
            <div style="color:#aaa;font-size:11px">${status}</div>
            <div>Miză: <b>0.40</b> RON</div>
            <div style="color:\( {col}">Profit: <b> \){profit >= 0 ? '+' : ''}${profit}</b></div>
            <div>Spin-uri: ${spinCount}</div>
            \( {msg ? `<div style="color:#ff0;margin-top:3px"> \){msg}</div>` : ''}
            \( {lastAction ? `<div style="color:#888;font-size:11px"> \){lastAction}</div>` : ''}
            <div style="color:#666;font-size:10px;margin-top:4px">F10 = Start/Stop | F11 = Overlay</div>
        `;
        overlay.style.opacity = showOverlay ? '1' : '0';
    }

    function setBet() {
        const input = $(sel.bet);
        if (!input) return;
        input.value = FIXED_BET.toFixed(2);
        input.dispatchEvent(new Event('input', { bubbles: true }));
        input.dispatchEvent(new Event('change', { bubbles: true }));
    }

    function doAction() {
        if (!isRunning) return;

        if ($(sel.feature)) {
            lastAction = 'FEATURE';
            updateOverlay();
            return;
        }

        const gambleBtn = $(sel.gamble);
        if (gambleBtn && gambleBtn.offsetParent !== null) {
            const winEl = document.querySelector('.last-win-amount, .win-value, .win-sum, .win-amount');
            let lastWin = 0;
            if (winEl) lastWin = parseFloat(winEl.textContent.replace(/[^0-9.]/g, '')) || 0;

            if (lastWin > 0 && lastWin <= GAMBLE_MAX && Math.random() < GAMBLE_CHANCE) {
                gambleBtn.click();
                lastAction = 'GAMBLE';
            } else {
                const collect = $(sel.collect);
                if (collect) collect.click();
                lastAction = 'COLLECT';
            }
            updateOverlay();
            return;
        }

        const spinBtn = $(sel.spin);
        if (spinBtn && !spinBtn.disabled) {
            setBet();
            setTimeout(() => {
                if (spinBtn && !spinBtn.disabled && isRunning) {
                    spinBtn.click();
                    spinCount++;
                    lastAction = 'SPIN';
                    updateOverlay();
                }
            }, 200 + Math.random() * 250);
        }
    }

    // Hotkeys
    document.addEventListener('keydown', e => {
        if (e.key === 'F10') {
            isRunning = !isRunning;
            if (isRunning) {
                startBalance = null;
                spinCount = 0;
                profit = 0;
                lastAction = 'PORNIT';
                console.log('%c[20 Burning Hot] BOT PORNIT – 0.40 RON', 'color:#0f0;font-size:14px');
            } else {
                lastAction = 'OPRIT';
                console.log('%c[20 Burning Hot] BOT OPRIT', 'color:#f55;font-size:14px');
            }
            updateOverlay();
        }

        if (e.key === 'F11') {
            showOverlay = !showOverlay;
            updateOverlay();
        }
    });

    setInterval(() => {
        if (isRunning) doAction();
    }, INTERVAL);

    createOverlay();
    updateOverlay('F10 = Start');
    console.log('%c20 Burning Hot 0.40 RON (Chrome PC) gata\nF10 = Start/Stop\nF11 = Overlay', 'color:#0f0;font-size:13px');
})();
