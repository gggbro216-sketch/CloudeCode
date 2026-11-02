// ПОДДЕЛКА SDK Яндекс Игр для проверки (на площадке её нет — там настоящий /sdk.js)
window.YaGames = { init: function () {
	console.log('MOCK init');
	const handlers = {};
	const store = JSON.parse(localStorage.getItem('mock_cloud') || '{}');
	return Promise.resolve({
		environment: { i18n: { lang: 'ru' } },
		on: function (n, f) { handlers[n] = f; },
		features: {
			LoadingAPI: { ready: function () { console.log('MOCK LoadingAPI.ready'); } },
			GameplayAPI: { start: function () { console.log('MOCK GameplayAPI.start'); }, stop: function () { console.log('MOCK GameplayAPI.stop'); } },
		},
		adv: {
			showFullscreenAdv: function (o) { console.log('MOCK fullscreen'); o.callbacks.onOpen(); setTimeout(function () { console.log('MOCK fullscreen close'); o.callbacks.onClose(true); }, 1500); },
			showRewardedVideo: function (o) { console.log('MOCK rewarded'); o.callbacks.onOpen(); setTimeout(function () { o.callbacks.onRewarded(); o.callbacks.onClose(); console.log('MOCK rewarded done'); }, 1500); },
		},
		getPlayer: function () { return Promise.resolve({
			setData: function (d) { console.log('MOCK setData ' + (d.save || '').length + ' байт'); localStorage.setItem('mock_cloud', JSON.stringify(d)); return Promise.resolve(); },
			getData: function () { console.log('MOCK getData'); return Promise.resolve(store); },
		}); },
	});
} };
