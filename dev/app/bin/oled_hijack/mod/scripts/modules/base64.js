function UTF8toUnicode(str) {
	// |[\xF8-\xFB][\x80-\xBF]{4}|[\xFC-\xFD][\x80-\xBF]{5}
	return str.replace(/[\xC0-\xDF][\x80-\xBF]|[\xE0-\xEF][\x80-\xBF]{2}|[\xF0-\xF7][\x80-\xBF]{3}/g, function (str) {
		return decodeURIComponent(escape(str));
	});
}

function UnicodetoUTF8(str) {
	return str.replace(/[^\x00-\xff]/g, function (str) {
		return unescape(encodeURIComponent(str));
	})
}

var base64_encode = function () {

	var BASE64CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

	return function (str) {
		var str = UnicodetoUTF8(str);
		
		var r = [],
			i = 0,
			t = 0,
			len = str.length,
			c;
		for (; i < len; i++) {
			if (++t === 3)
				t = 0;
			c = str.charCodeAt(i);

			switch (t) {
				case 1:
					r.push(c >> 2 & 0x3F);
					break;
				case 2:
					r.push(( str.charCodeAt(i - 1) << 4 | c >> 4 ) & 0x3F);
					break;
				case 0:
					r.push(( str.charCodeAt(i - 1) << 2 | c >> 6 ) & 0x3F);
					r.push(c & 0x3F);
					break;

			}

			if (i === len - 1 && t > 0) {
				r.push(c << ( ( 3 - t ) << 1 ) & 0x3F);
			}
		}

		for (var i = 0 , len = r.length; i < len; i++)
			r[i] = BASE64CHARS.charAt(r[i]);

		if (t)
			while (3 - t++ > 0)
				r.push('=');

		return r.join('');

	};
}();


var base64_decode = function () {

	var BASE64DECODER = [-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 62, -1, -1, -1, 63, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, -1, -1, -1, -1, -1, -1, -1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, -1, -1, -1, -1, -1, -1, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51];
	return function (str) {
		var r = [],
			i = 0 ,
			t = 0,
			c,
			n,
			len,
			off;

		i = 0;
		n = BASE64DECODER[str.charCodeAt(0)];
		len = str.length;

		while (i < len) {
			t++;
			c = n;
			n = BASE64DECODER[ str.charCodeAt(++i) ];

			if (n === -1) {
				i = len;
				n = 0;
			}

			r.push(c << ( t << 1 ) & 0xFF | n >> ( ( 3 - t ) << 1 ));

			if (t === 3) {
				i++;
				n = BASE64DECODER[ str.charCodeAt(i) ];
				t = 0;
			}
		}

		return UTF8toUnicode(String.fromCharCode.apply(String, r));
	}
}();

var Base64 = {
	encode: base64_encode,
	decode: base64_decode
};

export { Base64 };
