// ==UserScript==
// @name         20 Burning Hot – 0.40 RON (Firefox PC)
// @namespace    .
// @version      4.0
// @description  Auto-bet 0.40 RON | 20 Burning Hot | Firefox Desktop
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
