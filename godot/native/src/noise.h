// Двумерный симплекс-шум (по Густавсону) и фрактальная сумма октав, как у FastNoiseLite:
// FBM или «гребни» (ridged), лакунарность 2, усиление 0,5, своё зерно на октаву.
#pragma once

#include <cmath>
#include <cstdint>

class Simplex {
	uint8_t perm[512];

public:
	explicit Simplex(uint32_t seed) {
		uint8_t p[256];
		for (int i = 0; i < 256; i++) {
			p[i] = (uint8_t)i;
		}
		uint32_t s = seed * 2654435761u + 0x9e3779b9u;
		for (int i = 255; i > 0; i--) {
			s ^= s << 13;
			s ^= s >> 17;
			s ^= s << 5;
			int j = (int)(s % (uint32_t)(i + 1));
			uint8_t t = p[i];
			p[i] = p[j];
			p[j] = t;
		}
		for (int i = 0; i < 512; i++) {
			perm[i] = p[i & 255];
		}
	}

	float get(float xin, float yin) const {
		static const float G[12][2] = { { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 }, { 1, 0 }, { -1, 0 }, { 1, 0 }, { -1, 0 },
			{ 0, 1 }, { 0, -1 }, { 0, 1 }, { 0, -1 } };
		const float F2 = 0.36602540378f, G2 = 0.2113248654f;
		float s = (xin + yin) * F2;
		int i = (int)std::floor(xin + s), j = (int)std::floor(yin + s);
		float t = (i + j) * G2;
		float x0 = xin - (i - t), y0 = yin - (j - t);
		int i1 = x0 > y0 ? 1 : 0, j1 = x0 > y0 ? 0 : 1;
		float x1 = x0 - i1 + G2, y1 = y0 - j1 + G2;
		float x2 = x0 - 1.0f + 2.0f * G2, y2 = y0 - 1.0f + 2.0f * G2;
		int ii = i & 255, jj = j & 255;
		int g0 = perm[ii + perm[jj]] % 12, g1 = perm[ii + i1 + perm[jj + j1]] % 12, g2 = perm[ii + 1 + perm[jj + 1]] % 12;
		float n = 0.0f;
		float t0 = 0.5f - x0 * x0 - y0 * y0;
		if (t0 > 0.0f) {
			t0 *= t0;
			n += t0 * t0 * (G[g0][0] * x0 + G[g0][1] * y0);
		}
		float t1 = 0.5f - x1 * x1 - y1 * y1;
		if (t1 > 0.0f) {
			t1 *= t1;
			n += t1 * t1 * (G[g1][0] * x1 + G[g1][1] * y1);
		}
		float t2 = 0.5f - x2 * x2 - y2 * y2;
		if (t2 > 0.0f) {
			t2 *= t2;
			n += t2 * t2 * (G[g2][0] * x2 + G[g2][1] * y2);
		}
		return 70.0f * n;  // примерно −1…1
	}
};

class Fractal {
	static const int MAX = 8;
	Simplex *oct[MAX];
	int octaves;
	float freq, bounding;
	bool ridged;

public:
	Fractal(int32_t seed, float p_freq, int p_octaves, bool p_ridged) :
			octaves(p_octaves < MAX ? p_octaves : MAX), freq(p_freq), ridged(p_ridged) {
		float amp = 1.0f, sum = 0.0f;
		for (int o = 0; o < octaves; o++) {
			oct[o] = new Simplex((uint32_t)(seed + o));
			sum += amp;
			amp *= 0.5f;
		}
		bounding = 1.0f / sum;
	}
	~Fractal() {
		for (int o = 0; o < octaves; o++) {
			delete oct[o];
		}
	}
	Fractal(const Fractal &) = delete;
	Fractal &operator=(const Fractal &) = delete;

	float get(float x, float y) const {
		x *= freq;
		y *= freq;
		float sum = 0.0f, amp = bounding;
		for (int o = 0; o < octaves; o++) {
			float n = oct[o]->get(x, y);
			sum += ridged ? (std::fabs(n) * -2.0f + 1.0f) * amp : n * amp;
			x *= 2.0f;
			y *= 2.0f;
			amp *= 0.5f;
		}
		return sum;
	}
};
