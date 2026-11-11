	// ---------- авиация (подключается внутрь struct Step) ----------
	// Звено из трёх штурмовиков приходит по вызову, встаёт в круг над сектором вызвавшего (центр идёт за его
	// танком), само ищет танки противника в секторе и заходит на них: пушки с пикирования, бомбы с расчётом
	// сноса. Самолёт — сущность с моделью полёта и рулями: рули ставит ИИ звена либо игрок (air_input).
	// Самолёты сбивают 88-мм зенитки и зенитные пулемёты танков.
	enum { AS_INGRESS, AS_ORBIT, AS_ATTACK, AS_PULLOUT, AS_EGRESS, AS_CRASH };

	static V3 air_dir(const Core::Plane &p) {
		return { std::cos(p.yaw) * std::cos(p.pitch), std::sin(p.pitch), std::sin(p.yaw) * std::cos(p.pitch) };
	}

	// модель полёта: крен разворачивает, тангаж меняет высоту и скорость (в пикировании разгон, в наборе потеря)
	// полоса своей стороны: центр и высота
	// масштаб скорости: «скорость» самолёта — в условных единицах приборов (×0,9 = км/ч), а летит он в AIR_V раз
	// медленнее — иначе на карте в 4–6 км самолёт пересекал поле за 9 с (как в War Thunder: заход ~20 с)
	static constexpr float AIR_V = 0.5f;

	V3 air_field(int tm) const {
		float zc = tm == 0 ? c->ws + 380.0f : -380.0f;
		return { c->ws * 0.5f, c->height(c->ws * 0.5f, zc), zc };
	}

	// Прицелы игрока (как в War Thunder): точка падения бомбы (полёт с тяготением до земли) и точка встречи
	// очереди с землёй. Возвращает [бомба x,y,z, время падения, пушки x,y,z, дальность пушек (0 — нет встречи)].
	void air_sights(const Core::Plane &p, float *o) const {
		V3 b = { p.p.x, p.p.y - 4.0f, p.p.z }, v = p.v;
		float t = 0.0f;
		for (int i = 0; i < 600; i++) {
			const float h = 0.04f;
			V3 nv = { v.x, v.y - GRAVITY * h, v.z };
			V3 nb = v3add(b, v3mul(v3add(v, nv), 0.5f * h));
			t += h;
			float g = c->height(nb.x, nb.z);
			if (nb.y <= g) {
				float k = (b.y - c->height(b.x, b.z)) / std::max(0.001f, b.y - c->height(b.x, b.z) - (nb.y - g));
				b = v3add(b, v3mul(v3sub(nb, b), clampf(k, 0.0f, 1.0f)));
				break;
			}
			b = nb;
			v = nv;
		}
		o[0] = b.x; o[1] = c->height(b.x, b.z); o[2] = b.z; o[3] = t;
		V3 d = air_dir(p), s = v3add(p.p, v3mul(d, 14.0f)), sv = v3mul(d, 1900.0f + p.speed * AIR_V);
		o[4] = o[5] = o[6] = o[7] = 0.0f;
		for (int i = 0; i < 120; i++) {
			const float h = 0.01f;
			V3 nv = { sv.x, sv.y - GRAVITY * h, sv.z };
			V3 ns = v3add(s, v3mul(v3add(sv, nv), 0.5f * h));
			if (ns.y <= c->height(ns.x, ns.z)) {
				o[4] = ns.x; o[5] = c->height(ns.x, ns.z); o[6] = ns.z;
				o[7] = std::max(1.0f, v3len(v3sub(ns, p.p)));
				break;
			}
			s = ns;
			sv = nv;
		}
	}

	void air_fly(Core::Plane &p) {
		if (p.ground) {
			// на полосе: разбег по газу, отрыв на скорости взлёта; стоя — перезарядка и ремонт
			V3 f = air_field(p.team);
			p.pitch = 0.0f;
			p.roll = 0.0f;
			p.yaw = std::fabs(ang_diff(p.yaw, 0.0f)) < PI_F * 0.5f ? 0.0f : PI_F;
			p.speed = clampf(p.speed + (p.c_thr > 0.08f ? p.c_thr * 80.0f - 8.0f : -70.0f) * dt, 0.0f, 420.0f);
			p.p.x += std::cos(p.yaw) * p.speed * AIR_V * dt;
			p.p.z = f.z;
			p.p.y = f.y + 3.5f;
			p.v = { std::cos(p.yaw) * p.speed * AIR_V, 0.0f, 0.0f };
			if (p.speed > 235.0f && p.c_thr > 0.3f && (p.c_pitch > 0.1f || std::fabs(p.p.x - f.x) > 1500.0f)) {
				p.ground = false;
				p.pitch = 0.14f;
				p.p.y += 2.5f;
				p.rearm_t = 0.0f;
			} else if (std::fabs(p.p.x - f.x) > 1700.0f) {
				p.speed = 0.0f;  // выкатился за полосу
			}
			if (p.speed < 4.0f) {
				const Core::AirWeapon &w = c->air_w[p.team];
				int full_b = p.kind == 1 ? 0 : 2, full_r = p.kind == 1 ? 150 : std::min(w.rounds, 70);
				if (p.bombs < full_b || p.rounds < full_r || p.hp < p.hp0) {
					p.rearm_t += dt;
					if (p.rearm_t > 10.0f) {
						p.bombs = full_b;
						p.rounds = full_r;
						p.hp = p.hp0;
						p.rearm_t = 0.0f;
						ev.add({ (float)W_AIR, 5.0f, (float)p.team, p.p.x, p.p.y, p.p.z, (float)p.id });
					}
				}
			}
			return;
		}
		bool ftr = p.kind == 1;
		float roll_t = clampf(p.c_roll, -1.0f, 1.0f) * 1.15f;
		p.roll = move_toward(p.roll, roll_t, (ftr ? 2.2f : 1.6f) * dt);
		// срыв: на малой скорости рули вянут и нос падает
		float auth = clampf((p.speed - 150.0f) / 90.0f, 0.15f, 1.0f);
		p.yaw = wrapf(p.yaw + std::sin(p.roll) * (ftr ? 0.95f : 0.72f) * auth * dt, -PI_F, PI_F);
		p.pitch = clampf(p.pitch + clampf(p.c_pitch, -1.0f, 1.0f) * (ftr ? 0.75f : 0.6f) * auth * dt, -1.05f, 0.9f);
		if (p.speed < 175.0f) p.pitch -= (175.0f - p.speed) / 175.0f * 1.1f * dt;
		// тяга: повреждённый мотор тянет хуже; в вираже скорость теряется, в пикировании растёт
		float dmg_k = p.hp < p.hp0 * 0.4f ? 0.78f : 1.0f;
		float v_t = ((ftr ? 300.0f : 250.0f) + 230.0f * clampf(p.c_thr, 0.0f, 1.0f)) * dmg_k;
		if (p.c_thr < 0.05f) v_t = 150.0f;  // мотор на холостых: самолёт планирует и теряет скорость
		float drag = std::fabs(std::sin(p.roll)) * 38.0f;
		p.speed = clampf(p.speed + ((v_t - p.speed) * 0.45f - std::sin(p.pitch) * 170.0f - drag) * dt, 110.0f, 760.0f);
		V3 d = air_dir(p);
		p.v = v3mul(d, p.speed * AIR_V);
		p.p = v3add(p.p, v3mul(p.v, dt));
	}

	// посадка по автопилоту: выход на глиссаду вдоль полосы, снижение, выравнивание
	void air_land(Core::Plane &p) {
		V3 f = air_field(p.team);
		p.c_fire = false;
		p.c_bomb = false;
		if (std::getenv("STEEL_DEBUG_AIR") && ((int)(c->clock * 30.0f) % 15) == 0) {
			std::fprintf(stderr, "LAND ph=%d dx=%.0f dz=%.0f alt=%.0f gh=%.0f speed=%.0f pitch=%.2f roll=%.2f yaw=%.2f\n", p.land_ph, p.p.x - f.x, p.p.z - f.z, p.p.y - f.y, c->height(p.p.x, p.p.z) - f.y, p.speed, p.pitch, p.roll, p.yaw);
		}
		// садиться можно с любого торца: заход с той стороны, где самолёт был, когда включили автопилот
		if (p.tgt_plane != 1 && p.tgt_plane != -1) p.tgt_plane = p.p.x < f.x ? 1 : -1;
		float sd = (float)p.tgt_plane, h0 = sd > 0.0f ? 0.0f : PI_F;
		if (p.land_ph == 0) {
			// выход в точку начала захода: далеко перед торцом, чтобы успеть встать на ось
			V3 a0 = { f.x - sd * 2500.0f, f.y + 200.0f, f.z };
			air_steer(p, a0);
			p.c_thr = 0.5f;
			if (std::hypot(p.p.x - a0.x, p.p.z - a0.z) < 300.0f) p.land_ph = 1;
		} else {
			float along = sd * (p.p.x - (f.x - sd * 560.0f));  // до торца полосы (отрицательно — ещё не долетел)
			float lat = f.z - p.p.z;
			// курс: вдоль полосы с пологим выходом на ось (угол перехвата до 35°)
			float want_yaw = h0 + sd * clampf(lat / 500.0f, -0.6f, 0.6f);
			float yerr = ang_diff(want_yaw, p.yaw);
			p.c_roll = clampf(yerr * 2.0f, -0.9f, 0.9f);
			bool lined = std::fabs(lat) < 60.0f && std::fabs(ang_diff(h0, p.yaw)) < 0.18f;
			// высота: по глиссаде, пока стоит на оси; иначе держит 150 и не снижается
			float want_h = f.y + (lined || along > -250.0f ? 3.0f + std::max(0.0f, std::min(200.0f, -along * 0.15f)) : 150.0f);
			float dp = clampf((want_h - p.p.y) / 260.0f, -0.28f, 0.3f);
			if (p.p.y - f.y < 14.0f && along > -200.0f) {
				dp = -0.035f;  // выравнивание: пологое касание
				p.c_thr = 0.0f;
			}
			p.c_pitch = clampf((dp - p.pitch) * 3.0f, -1.0f, 1.0f);
			if (!(p.p.y - f.y < 14.0f && along > -200.0f)) p.c_thr = p.speed > 270.0f ? 0.0f : 0.3f;
			// не попал на ось к торцу — уход на второй круг
			if (along > -150.0f && along < 600.0f && !lined && p.p.y - f.y > 12.0f) {
				p.land_ph = 0;
				p.tgt_plane = 0;
			}
			if (along > 2200.0f) {
				p.land_ph = 0;
				p.tgt_plane = 0;
			}
		}
	}

	// рули — на точку
	void air_steer(Core::Plane &p, V3 to) {
		float err = ang_diff(std::atan2(to.z - p.p.z, to.x - p.p.x), p.yaw);
		p.c_roll = clampf(err * 1.7f, -1.0f, 1.0f);
		float hd = std::max(1.0f, std::hypot(to.x - p.p.x, to.z - p.p.z));
		float dp = clampf(std::atan2(to.y - p.p.y, hd), -0.8f, 0.55f);
		p.c_pitch = clampf((dp - p.pitch) * 2.6f, -1.0f, 1.0f);
	}

	// очередь из пушек вдоль оси самолёта: настоящие снаряды (по крыше броня тоньше)
	void air_gun(Core::Plane &p) {
		Core::AirWeapon w = c->air_w[p.team];
		if (p.kind == 1) {
			// истребитель: пушки 20 мм, часто и слабо
			w.cal = 20.0f;
			w.pen = 20.0f;
			w.dmg = 14.0f;
			w.rof = 12.0f;
		}
		p.firing = false;
		p.gun_t -= dt;
		if (p.rounds <= 0) return;
		p.firing = true;
		while (p.gun_t <= 0.0f && p.rounds > 0) {
			p.gun_t += 1.0f / w.rof;
			p.rounds--;
			V3 d = air_dir(p);
			float sx = randn() * 0.006f, sy = randn() * 0.006f;
			V3 dir = v3norm({ d.x + sx, d.y + sy, d.z - sx });
			Core::Shell sh;
			sh.pos = v3add(p.p, v3mul(d, 14.0f));
			sh.vel = v3mul(dir, 1900.0f + p.speed * AIR_V);
			sh.dist = 0.0f;
			sh.rico = 0;
			sh.owner = -1;
			sh.team = p.team;
			sh.src_plane = p.id;
			sh.kind = AM_AP;
			sh.cal = w.cal;
			sh.pen = w.pen;
			sh.dmg = w.dmg;
			sh.he = 0.0f;
			int slot = c->w.shell_slot;
			c->w.shell_slot = (slot + 1) % 64;
			sh.slot = slot;
			if (c->shells.size() < 512) c->shells.push_back(sh);
			ev.add({ (float)W_INF_SHOT, 9.0f, sh.pos.x, sh.pos.y, sh.pos.z, dir.x, dir.y, dir.z, (float)slot, v3len(sh.vel), -1.0f, w.cal });
		}
	}

	void air_bomb(Core::Plane &p) {
		if (p.bombs <= 0 || p.bomb_cd > 0.0f) return;
		const Core::AirWeapon &w = c->air_w[p.team];
		p.bomb_cd = 1.5f;
		// залп: две бомбы с крыльев (последняя — одна)
		int salvo = std::min(2, p.bombs);
		for (int b = 0; b < salvo; b++) {
		p.bombs--;
		float side = salvo == 2 ? (b == 0 ? -14.0f : 14.0f) : 0.0f;
		Core::Shell sh;
		sh.pos = { p.p.x - std::sin(p.yaw) * side, p.p.y - 4.0f, p.p.z + std::cos(p.yaw) * side };
		sh.vel = { p.v.x + (b == 0 ? 6.0f : -6.0f), p.v.y, p.v.z };
		sh.dist = 0.0f;
		sh.rico = 0;
		sh.owner = p.by;
		sh.team = p.team;
		sh.kind = AM_HE;
		sh.cal = w.bomb_cal;
		sh.he = 15000.0f;
		sh.dmg = 600.0f;
		sh.pen = 70.0f;
		int slot = c->w.shell_slot;
		c->w.shell_slot = (slot + 1) % 64;
		sh.slot = slot;
		if (c->shells.size() < 512) c->shells.push_back(sh);
		V3 dir = v3norm(sh.vel);
		ev.add({ (float)W_INF_SHOT, 8.0f, sh.pos.x, sh.pos.y, sh.pos.z, dir.x, dir.y, dir.z, (float)slot, v3len(sh.vel), -1.0f, w.bomb_cal });
		}
	}

	// цель звену: танк противника в секторе, которого видит команда или сам лётчик; по одному самолёту на цель
	int air_find(const Core::Plane &p, int self_i) {
		int best = -1;
		float bd = 1e9f;
		for (int i = 0; i < n(); i++) {
			if (!c->td[i].alive || team(i) == p.team) continue;
			float dh = std::hypot(T(i)[P_X] - p.hold.x, T(i)[P_Y] - p.hold.z);
			if (dh > 780.0f) continue;
			bool seen = T(i)[p.team == 0 ? P_VIS0 : P_VIS1] != 0.0f;
			if (!seen) {
				V3 tp = top(i);
				if (std::hypot(tp.x - p.p.x, tp.z - p.p.z) > 950.0f || !c->los(p.p, tp) || c->smoke_blocks(p.p, tp)) continue;
			}
			float sc = dh;
			for (size_t j = 0; j < c->planes.size(); j++) {
				const Core::Plane &o = c->planes[j];
				if ((int)j != self_i && o.alive && o.flight == p.flight && o.state == AS_ATTACK && o.tgt == i) sc += 500.0f;
			}
			if (sc < bd) {
				bd = sc;
				best = i;
			}
		}
		return best;
	}

	void air_ai(Core::Plane &p, int idx) {
		float gh = c->height(p.p.x, p.p.z);
		if (p.by >= 0 && p.by < n() && c->td[p.by].alive) {
			p.hold.x = T(p.by)[P_X];
			p.hold.z = T(p.by)[P_Y];
		}
		float hgh = c->height(p.hold.x, p.hold.z);
		float alt = 300.0f + 22.0f * (float)p.slot;
		p.c_fire = false;
		p.c_bomb = false;
		p.c_thr = 0.85f;
		p.t += dt;
		switch (p.state) {
			case AS_INGRESS: {
				air_steer(p, { p.hold.x, hgh + alt, p.hold.z });
				if (std::hypot(p.hold.x - p.p.x, p.hold.z - p.p.z) < 620.0f) {
					p.state = AS_ORBIT;
					p.t = 0.0f;
					if (p.slot == 0) ev.add({ (float)W_AIR, 0.0f, (float)p.team, p.hold.x, hgh, p.hold.z });
				}
				break;
			}
			case AS_ORBIT: {
				float a = std::atan2(p.p.z - p.hold.z, p.p.x - p.hold.x) + 0.55f;
				air_steer(p, { p.hold.x + std::cos(a) * 520.0f, hgh + alt, p.hold.z + std::sin(a) * 520.0f });
				p.c_thr = 0.6f;
				p.think_t -= dt;
				if (p.think_t <= 0.0f) {
					p.think_t = 0.8f;
					if (c->clock > p.leave_t || (p.bombs <= 0 && p.rounds <= 0) || c->w.over) {
						p.state = AS_EGRESS;
						if (p.slot == 0) ev.add({ (float)W_AIR, 4.0f, (float)p.team, p.p.x, p.p.y, p.p.z });
						break;
					}
					int tg = p.t > 1.5f ? air_find(p, idx) : -1;
					if (tg >= 0) {
						p.tgt = tg;
						p.state = AS_ATTACK;
						p.t = 0.0f;
						p.burst = 0.0f;
						p.dive = false;
						p.ext = false;
						if (p.team == 0) c->td[tg].lit = std::max(c->td[tg].lit, 2.5f);
					}
				}
				break;
			}
			case AS_ATTACK: {
				if (p.tgt < 0 || p.tgt >= n() || !c->td[p.tgt].alive || p.t > 28.0f) {
					p.state = AS_PULLOUT;
					p.t = 0.0f;
					break;
				}
				V3 tp = center(p.tgt);
				float hd = std::hypot(tp.x - p.p.x, tp.z - p.p.z);
				float lead = hd / std::max(p.speed * AIR_V, 1.0f);
				tp.x += T(p.tgt)[P_VX] * lead;
				tp.z += T(p.tgt)[P_VY] * lead;
				hd = std::hypot(tp.x - p.p.x, tp.z - p.p.z);
				float herr = std::fabs(ang_diff(std::atan2(tp.z - p.p.z, tp.x - p.p.x), p.yaw));
				bool bombing = p.bombs > 0;
				if (std::getenv("STEEL_DEBUG_AIR") && idx == 0 && ((int)(c->clock * 30.0f) % 15) == 0) {
					std::fprintf(stderr, "AIR t=%.1f tgt=%d dive=%d hd=%.0f herr=%.2f alt=%.0f pitch=%.2f speed=%.0f bombs=%d\n", p.t, p.tgt, p.dive ? 1 : 0, hd, herr, p.p.y - gh, p.pitch, p.speed, p.bombs);
				}
				if (!p.dive) {
					// построение захода: слишком близко и не на курсе — отойти по прямой, затем развернуться на цель
					if (hd < 650.0f && herr > 0.3f) p.ext = true;
					if (p.ext && hd > 1150.0f) p.ext = false;
					if (p.ext) {
						V3 d0 = air_dir(p);
						air_steer(p, { p.p.x + d0.x * 600.0f, tp.y + 280.0f, p.p.z + d0.z * 600.0f });
					} else {
						air_steer(p, { tp.x, tp.y + 280.0f, tp.z });
						p.c_thr = herr > 0.4f ? 0.2f : 0.6f;  // в развороте — малый газ, радиус меньше
					}
					if (!p.ext && herr < 0.25f && hd < 1150.0f && hd > 380.0f) p.dive = true;
					break;
				}
				// пикирование: с бомбами целится чуть выше цели (бомба недолетает до линии прицела), без бомб — точно в цель
				air_steer(p, bombing ? V3{ tp.x, tp.y + 0.1f * hd + 8.0f, tp.z } : tp);
				p.c_thr = 0.25f;
				V3 d = air_dir(p), to = v3norm(v3sub(tp, p.p));
				float off = std::acos(clampf(v3dot(d, to), -1.0f, 1.0f));
				if (off < (bombing ? 0.16f : 0.07f) && hd < 640.0f && hd > 110.0f && p.burst < 1.8f) {
					p.c_fire = true;
					p.burst += dt;
				}
				// бомбы: сброс, когда снос по горизонтали равен дальности до цели
				if (bombing && herr < 0.09f) {
					float h = p.p.y - tp.y, vd = -p.v.y;
					float tf = (-vd + std::sqrt(std::max(0.0f, vd * vd + 2.0f * GRAVITY * h))) / GRAVITY;
					float carry = std::hypot(p.v.x, p.v.z) * tf;
					if (std::fabs(hd - carry) < 28.0f && h > 35.0f) p.c_bomb = true;
				}
				if (p.p.y - gh < 62.0f || hd < 110.0f || (p.pitch < -0.15f && (p.p.y - gh) / std::max(1.0f, -p.v.y) < 1.1f)) {
					p.state = AS_PULLOUT;
					p.t = 0.0f;
				}
				break;
			}
			case AS_PULLOUT: {
				p.c_pitch = p.pitch < 0.42f ? 1.0f : 0.0f;
				p.c_roll = p.t > 1.0f ? ((p.slot & 1) ? 0.5f : -0.5f) : 0.0f;
				p.c_thr = 1.0f;
				if (p.p.y - gh > 230.0f || p.t > 5.0f) {
					p.state = AS_ORBIT;
					p.tgt = -1;
					p.t = 0.0f;
					p.think_t = 1.2f;
				}
				break;
			}
			case AS_EGRESS: {
				air_steer(p, { p.hold.x, hgh + 420.0f, p.team == 0 ? c->ws + 2200.0f : -2200.0f });
				p.c_thr = 1.0f;
				break;
			}
			default:
				break;
		}
		// земля близко — вверх, что бы ни делал
		if (p.state != AS_ATTACK && p.p.y - gh < 70.0f) p.c_pitch = 1.0f;
	}

	// зенитный огонь: 88-мм зенитки и пулемёты танков
	void air_aa(Core::Plane &p) {
		p.aa_t -= dt;
		if (p.aa_t > 0.0f) return;
		p.aa_t = 0.5f;
		float gh = c->height(p.p.x, p.p.z);
		float dmg = 0.0f;
		if (p.p.y - gh < 430.0f) {
			for (int i = 0; i < n(); i++) {
				if (!c->td[i].alive || team(i) == p.team || !c->td[i].gun_crew) continue;
				if (std::hypot(T(i)[P_X] - p.p.x, T(i)[P_Y] - p.p.z) < 480.0f && randf() < 0.035f) dmg += rnd(10.0f, 24.0f);
			}
		}
		for (const Core::Soldier &s : c->inf) {
			if (!s.alive || s.role != IR_GUN || s.team == p.team || s.squad < 0 || (size_t)s.squad >= c->isq.size()) continue;
			if (c->isq[s.squad].nat / 64 != 2) continue;  // только 88-мм зенитка
			if (std::hypot(s.x - p.p.x, s.y - p.p.z) < 1400.0f && randf() < 0.3f) {
				V3 puff = { p.p.x + rnd(-40.0f, 40.0f), p.p.y + rnd(-25.0f, 25.0f), p.p.z + rnd(-40.0f, 40.0f) };
				ev.add({ (float)W_AIR, 3.0f, (float)p.team, puff.x, puff.y, puff.z });
				if (randf() < 0.45f) dmg += rnd(35.0f, 65.0f);
			}
		}
		if (dmg > 0.0f) {
			p.hp -= dmg;
			if (p.hp <= 0.0f && p.state != AS_CRASH) {
				p.state = AS_CRASH;
				p.player = false;
				ev.add({ (float)W_AIR, 2.0f, (float)p.team, p.p.x, p.p.y, p.p.z });
			}
		}
	}

	void air_step() {
		// заявки: звено из трёх заходит со стороны своей базы
		for (const Core::AirReq &q : c->air_req) {
			int flight = c->air_flights++;
			float zs = q.team == 0 ? c->ws + 1300.0f : -1300.0f, back = q.team == 0 ? 1.0f : -1.0f;
			const Core::AirWeapon &w = c->air_w[q.team];
			for (int j = 0; j < 3; j++) {
				Core::Plane p;
				p.id = ++c->air_ids;
				p.hp0 = w.hp;
				p.team = q.team;
				p.flight = flight;
				p.slot = j;
				p.by = q.by;
				p.hold = { q.x, 0.0f, q.z };
				p.p = { clampf(q.x + (float)(j - 1) * 170.0f, -400.0f, c->ws + 400.0f), c->height(q.x, q.z) + 340.0f + 25.0f * (float)j, zs + back * 430.0f * (float)j };
				p.yaw = q.team == 0 ? -PI_F * 0.5f : PI_F * 0.5f;
				p.hp = w.hp;
				p.bombs = w.bombs;
				p.rounds = w.rounds;
				p.leave_t = c->clock + 115.0f;
				c->planes.push_back(p);
			}
			float eta = std::fabs(zs - q.z) / 440.0f;
			ev.add({ (float)W_STRIKE, 1.0f, (float)q.team, q.x, q.z, eta, 0.0f, -back, (float)q.by });
		}
		c->air_req.clear();
		for (size_t k = 0; k < c->planes.size(); k++) {
			Core::Plane &p = c->planes[k];
			if (!p.alive) continue;
			p.bomb_cd = std::max(0.0f, p.bomb_cd - dt);
			if (p.state == AS_CRASH) {
				p.c_pitch = -0.7f;
				p.c_roll = 1.0f;
				p.c_thr = 0.2f;
				p.roll += 1.6f * dt;
			} else if (p.player && p.landing && !p.ground) {
				air_land(p);
			} else if (!p.player) {
				if (p.kind == 1) {
					air_fighter(p);
				} else {
					air_ai(p, (int)k);
				}
			}
			if (p.state != AS_CRASH) {
				if (p.c_fire) {
					air_gun(p);
				} else {
					p.firing = false;
					p.gun_t = std::max(0.0f, p.gun_t - dt);
				}
				if (p.c_bomb) air_bomb(p);
				air_aa(p);
			}
			air_fly(p);
			float gh = c->height(p.p.x, p.p.z);
			if (p.ground) continue;
			if (p.p.y <= gh + 3.6f && p.state != AS_CRASH) {
				// касание: на своей полосе, полого, без крена и не слишком быстро — посадка
				V3 f = air_field(p.team);
				bool strip = std::fabs(p.p.x - f.x) < 1700.0f && std::fabs(p.p.z - f.z) < 90.0f;
				if (strip && p.v.y < -1.0f && p.v.y > -85.0f && p.speed < 380.0f && std::fabs(p.roll) < 0.4f && std::fabs(ang_diff(p.yaw, std::fabs(ang_diff(p.yaw, 0.0f)) < PI_F * 0.5f ? 0.0f : PI_F)) < 0.45f) {
					p.ground = true;
					p.landing = false;
					p.land_ph = 0;
					p.tgt_plane = -9;
					p.c_thr = 0.0f;
					ev.add({ (float)W_AIR, 7.0f, (float)p.team, p.p.x, p.p.y, p.p.z, (float)p.id });
					continue;
				}
			}
			if (p.p.y <= gh + 3.0f && !(p.v.y >= 0.0f && p.p.y > gh + 1.0f)) {
				// разбился: взрыв как у бомбы
				p.alive = false;
				p.gone = true;
				V3 at = { p.p.x, gh + 2.0f, p.p.z };
				ev.add({ (float)W_AIR, 1.0f, (float)p.team, at.x, at.y, at.z });
				inf_blast(at, 150.0f, 8000.0f, -1);
			} else if (p.p.z < -1900.0f || p.p.z > c->ws + 1900.0f || p.p.x < -2500.0f || p.p.x > c->ws + 2500.0f) {
				if (p.state == AS_EGRESS || p.state == AS_CRASH) {
					p.alive = false;
					p.gone = true;
				}
			}
		}
		c->planes.erase(std::remove_if(c->planes.begin(), c->planes.end(), [](const Core::Plane &p) { return p.gone; }), c->planes.end());
		air_hits();
		// истребители-перехватчики ИИ отключены (лишние): air_cap() не вызывается
	}

	// снаряды по самолётам: любой снаряд противника (танк, ЗСУ, пушка, самолёт), прошедший рядом с корпусом
	void air_hits() {
		if (c->planes.empty()) return;
		for (Core::Shell &s : c->shells) {
			if (s.dead || s.kind == AM_SMOKE) continue;
			int st = s.owner >= 0 && s.owner < n() ? team(s.owner) : s.team;
			V3 seg = v3mul(s.vel, dt);
			for (Core::Plane &p : c->planes) {
				if (!p.alive || p.team == st || p.state == AS_CRASH || p.id == s.src_plane) continue;
				V3 rel = v3sub(p.p, s.pos);
				if (std::fabs(rel.x) > 900.0f || std::fabs(rel.z) > 900.0f) continue;
				V3 cl = closest_on(p.p, s.pos, seg);
				float r = p.ground ? 16.0f : 13.0f;
				if (v3len(v3sub(cl, p.p)) > r) continue;
				float dmg = s.cal < 15.0f ? 9.0f : (s.cal < 25.0f ? 19.0f : (s.cal < 45.0f ? 46.0f : 400.0f));
				p.hp -= dmg * rnd(0.7f, 1.3f);
				s.dead = true;
				ev.add({ (float)W_AIR, 6.0f, (float)p.team, cl.x, cl.y, cl.z, (float)p.id });
				if (p.hp <= 0.0f) {
					bool by_player = (s.owner >= 0 && s.owner == c->w.player);
					for (const Core::Plane &o : c->planes) by_player = by_player || (o.id == s.src_plane && o.player);
					if (by_player && p.team == 1) c->air_kills++;
					if (p.ground) {
						p.alive = false;
						p.gone = true;
						ev.add({ (float)W_AIR, 1.0f, (float)p.team, p.p.x, p.p.y, p.p.z, (float)p.id });
					} else {
						p.state = AS_CRASH;
						p.player = false;
						ev.add({ (float)W_AIR, 2.0f, (float)p.team, p.p.x, p.p.y, p.p.z, (float)p.id });
					}
				}
				break;
			}
		}
	}

	// истребитель ИИ: ищет самолёт противника, заходит в хвост с упреждением, бьёт с 70 м; без целей уходит
	void air_fighter(Core::Plane &p) {
		float gh = c->height(p.p.x, p.p.z);
		p.c_fire = false;
		p.c_bomb = false;
		p.c_thr = 1.0f;
		p.t += dt;
		Core::Plane *tg = nullptr;
		float bd = 1e9f;
		for (Core::Plane &o : c->planes) {
			if (!o.alive || o.team == p.team || o.state == AS_CRASH || o.ground) continue;
			float d = v3len(v3sub(o.p, p.p));
			if (d < bd) {
				bd = d;
				tg = &o;
			}
		}
		if (p.state == AS_EGRESS || (!tg && p.t > 25.0f) || p.rounds <= 0 || p.hp < p.hp0 * 0.3f) {
			p.state = AS_EGRESS;
			air_steer(p, { c->ws * 0.5f, gh + 450.0f, p.team == 0 ? c->ws + 2300.0f : -2300.0f });
			return;
		}
		if (!tg) {
			// барраж над своей половиной
			float cz = p.team == 0 ? c->ws * 0.7f : c->ws * 0.3f;
			float a = std::atan2(p.p.z - cz, p.p.x - c->ws * 0.5f) + 0.5f;
			air_steer(p, { c->ws * 0.5f + std::cos(a) * 700.0f, c->height(c->ws * 0.5f, cz) + 380.0f, cz + std::sin(a) * 700.0f });
			p.c_thr = 0.6f;
			return;
		}
		p.t = 0.0f;
		float lead = bd / (1900.0f + p.speed * AIR_V);
		V3 aim = v3add(tg->p, v3mul(tg->v, lead));
		aim.y = std::max(aim.y, c->height(aim.x, aim.z) + 60.0f);
		air_steer(p, aim);
		if (bd < 260.0f) p.c_thr = 0.45f;
		V3 d = air_dir(p), to = v3norm(v3sub(aim, p.p));
		if (bd < 560.0f && std::acos(clampf(v3dot(d, to), -1.0f, 1.0f)) < 0.055f) p.c_fire = true;
		if (p.p.y - gh < 75.0f) p.c_pitch = 1.0f;
	}

	// перехват: авиация противника висит над полем — сторона поднимает пару истребителей
	void air_cap() {
		for (int tm = 0; tm < 2; tm++) {
			c->cap_cd[tm] = std::max(0.0f, c->cap_cd[tm] - dt);
			int foes = 0, mine = 0;
			for (const Core::Plane &p : c->planes) {
				if (!p.alive || p.ground || p.state == AS_CRASH) continue;
				if (p.team != tm) foes++;
				if (p.team == tm && p.kind == 1 && !p.player) mine++;
			}
			c->cap_t[tm] = foes > 0 ? c->cap_t[tm] + dt : 0.0f;
			if (c->cap_t[tm] < 16.0f || mine > 0 || c->cap_cd[tm] > 0.0f || c->w.over) continue;
			c->cap_cd[tm] = 110.0f;
			c->cap_t[tm] = 0.0f;
			float zs = tm == 0 ? c->ws + 1500.0f : -1500.0f;
			for (int j = 0; j < 2; j++) {
				Core::Plane p;
				p.id = ++c->air_ids;
				p.team = tm;
				p.kind = 1;
				p.flight = -1000 - p.id;
				p.slot = j;
				p.p = { c->ws * 0.5f + (j == 0 ? -150.0f : 150.0f), c->height(c->ws * 0.5f, tm == 0 ? c->ws : 0.0f) + 420.0f, zs + (tm == 0 ? 1.0f : -1.0f) * 300.0f * (float)j };
				p.yaw = tm == 0 ? -PI_F * 0.5f : PI_F * 0.5f;
				p.speed = 480.0f;
				p.hp = p.hp0 = 80.0f;
				p.bombs = 0;
				p.rounds = 150;
				p.state = AS_ORBIT;
				c->planes.push_back(p);
			}
			ev.add({ (float)W_AIR, 8.0f, (float)tm, c->ws * 0.5f, 0.0f, zs });
		}
	}
