const ws = new WebSocket(window.location.origin.replace(/^http/, 'ws'));
ws.onmessage = (e) => console.log('received:', e.data);
ws.onopen = () => ws.send('hi from tab 1');
