// RandomNumberGenerator Godot (RandomPCG, PCG32): то же зерно — те же числа, что у GDScript.
#pragma once

#include <cmath>
#include <cstdint>

struct GRng {
	uint64_t state = 0, inc = 0;
	void seed(uint64_t s) {
		inc = (1442695040888963407ULL << 1u) | 1u;
		state = 0;
		next();
		state += s;
		next();
	}
	uint32_t next() {
		uint64_t old = state;
		state = old * 6364136223846793005ULL + inc;
		uint32_t xs = (uint32_t)(((old >> 18u) ^ old) >> 27u);
		uint32_t rot = (uint32_t)(old >> 59u);
		return (xs >> rot) | (xs << ((-rot) & 31));
	}
	double randf() {
		uint32_t proto = next();
		if (proto == 0) return 0.0;
		return (double)std::ldexp((float)(next() | 0x80000001u), -32 - __builtin_clz(proto));
	}
	double range(float a, float b) {
		float f = (float)randf();
		return (double)(f * (b - a) + a);
	}
	int64_t randi() { return (int64_t)next(); }
};

