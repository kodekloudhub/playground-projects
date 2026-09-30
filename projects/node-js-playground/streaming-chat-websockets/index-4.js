const ws2 = new WebSocket(window.location.origin.replace(/^http/, 'ws'));
ws2.onmessage = (e) => console.log('received:', e.data);
ws2.onopen = () => ws2.send('hi from tab 2');
