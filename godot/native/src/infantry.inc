	// ---------- пехота (подключается внутрь struct Step) ----------
	// Отделение идёт за своими танками по направлению, при контакте бойцы занимают укрытия и ведут огонь.
	// Стрелки и автоматчики бьют по пехоте (упрощённо, вероятностью), ПТ-ружья, гранатомёты и «фаусты»
	// выпускают настоящие снаряды по танкам. Пехоту косят пулемёты танков, осколки фугасов и гусеницы.

	float inf_eye(const Core::Soldier &s) const { return s.gh + (s.state == IS_PRONE || s.state == IS_CRAWL ? 2.5f : (s.state == IS_KNEEL || s.state == IS_CROUCH ? 7.5f : 12.0f)); }
	float inf_chest(const Core::Soldier &s) const { return s.gh + (s.state == IS_PRONE || s.state == IS_CRAWL ? 1.6f : (s.state == IS_KNEEL || s.state == IS_CROUCH ? 5.0f : 9.0f)); }
	bool inf_low(const Core::Soldier &s) const { return s.state == IS_PRONE || s.state == IS_CRAWL; }

	// с какого расстояния бойца видно
	float inf_vis_range(const Core::Soldier &s) const {
		float r = inf_low(s) ? 290.0f : (s.state == IS_KNEEL || s.state == IS_CROUCH ? 440.0f : 640.0f);
		if (s.role == IR_GUN) r = 470.0f;
		if (c->in_bush(s.x, s.y)) r *= 0.55f;
		if (s.fired_t < 2.0f) r = std::max(r, s.role == IR_GUN ? 900.0f : 560.0f);
		return r;
	}

	// насколько трудно попасть (поза, укрытие)
	float inf_cover_k(const Core::Soldier &s) const {
		float k = inf_low(s) ? 0.42f : (s.state == IS_KNEEL || s.state == IS_CROUCH ? 0.7f : (s.state == IS_RUN ? 0.8f : 1.0f));
		if (s.role == IR_GUN) k = 0.55f;  // расчёт за щитом
		if (s.has_cover && s.still_t > 0.3f) k *= 0.6f;
		if (c->in_bush(s.x, s.y)) k *= 0.75f;
		return k;
	}

	void inf_kill(int k, int by, int cause) {
		Core::Soldier &s = c->inf[k];
		if (!s.alive) return;
		if (s.role == IR_GUN && cause != 2) {
			// пушка: выбывает расчёт по одному (осколки — сразу двое), орудие замолкает без людей
			s.ammo -= cause == 1 ? 2 : 1;
			s.sup = std::min(1.0f, s.sup + 0.5f);
			if (s.ammo > 0) return;
			s.ammo = 0;
		}
		s.alive = false;
		s.state = (cause == 2 || randf() < 0.5f) ? IS_DEAD_F : IS_DEAD_B;
		s.dead_t = 0.0f;
		if (s.squad >= 0 && (size_t)s.squad < c->isq.size()) c->isq[s.squad].alive--;
		if (by >= 0 && by == c->w.player && s.team == 1) c->inf_kills++;
		ev.add({ (float)W_INF_DEAD, (float)k, (float)by, (float)cause, s.x, s.gh, s.y, (float)s.team });
	}

	void inf_suppress(float x, float y, float r, float amount, int team_hit) {
		for (Core::Soldier &o : c->inf) {
			if (!o.alive || o.team != team_hit) continue;
			float dx = o.x - x, dy = o.y - y;
			if (dx * dx + dy * dy < r * r) o.sup = std::min(1.0f, o.sup + amount);
		}
	}

	// разрыв: осколки и подавление
	void inf_blast(V3 p, float cal, float he, int by) {
		if (c->inf.empty()) return;
		float R = he > 0.0f ? c->upm * clampf(1.2f + cal * 0.042f, 2.5f, 9.0f) : c->upm * 0.9f;
		for (size_t k = 0; k < c->inf.size(); k++) {
			Core::Soldier &o = c->inf[k];
			if (!o.alive) continue;
			float dx = o.x - p.x, dy = o.y - p.z, dh = (o.gh + 4.0f) - p.y;
			float d2 = dx * dx + dy * dy + dh * dh * 0.5f;
			if (d2 > R * R * 36.0f) continue;
			float d = std::sqrt(d2);
			bool low = inf_low(o);
			float pk = 0.0f;
			if (d < R) {
				pk = low ? 0.62f : 0.94f;
			} else if (d < R * 2.5f && he > 0.0f) {
				pk = (low ? 0.07f : 0.32f) * (1.0f - (d - R) / (R * 1.5f));
			}
			if (o.has_cover && d > R * 0.6f) pk *= 0.6f;
			if (pk > 0.0f && randf() < pk) {
				inf_kill((int)k, by, 1);
			} else if (he > 0.0f || d < R * 3.0f) {
				o.sup = std::min(1.0f, o.sup + (d < R * 3.0f ? 0.8f : 0.4f));
			}
		}
	}

	// маршрут и рубеж отделения — раз в секунду
	void inf_squad_plan(int qi) {
		Core::InfSquad &q = c->isq[qi];
		if (q.alive <= 0) return;
		if (q.hold) return;
		if (c->mode == 3 && !c->zones.empty()) {
			// прорыв: атака идёт к текущему сектору, оборона занимает его и отходит к следующему
			int z = std::min(std::max(c->bt_cur, 0), (int)c->zones.size() - 1);
			int key = 100 + z;
			if (key == q.stage) return;
			q.stage = key;
			float back = q.team == c->bt_att ? (q.team == 0 ? 60.0f : -60.0f) : (q.team == 0 ? 90.0f : -90.0f);
			V2 to = { clampf(c->zones[z].x + q.side * 0.6f, 60.0f, c->ws - 60.0f), clampf(c->zones[z].y + back, 60.0f, c->ws - 60.0f) };
			q.path = c->nav_path({ q.ax, q.ay }, to, true, 6.0f);
			if (q.path.empty()) q.path.push_back(to);
			q.pi = 0;
			return;
		}
		if (c->hold_team[q.team]) return;
		int st = std::min(c->squads[q.team][q.lane].stage, c->max_stage());
		if (st == q.stage && !q.path.empty()) return;
		if (st == q.stage && q.pi >= (int)q.path.size()) return;
		q.stage = st;
		V2 to = c->stage_point(q.team, q.lane, st);
		V2 alt = { clampf(to.x + q.side, 60.0f, c->ws - 60.0f), to.y };
		if (!c->blocked_at(alt.x, alt.y, 8.0f)) to = alt;
		V2 from = { q.ax, q.ay };
		q.path = c->nav_path(from, to, true, 6.0f);
		if (q.path.empty()) q.path.push_back(to);
		q.pi = 0;
	}

	void inf_squad_move(int qi) {
		Core::InfSquad &q = c->isq[qi];
		q.contact_t = std::max(0.0f, q.contact_t - dt);
		if (q.alive <= 0 || q.pi >= (int)q.path.size()) return;
		// свои не отстали?
		float cx = 0.0f, cy = 0.0f;
		int nn = 0;
		for (const Core::Soldier &s : c->inf) {
			if (s.alive && s.squad == qi) {
				cx += s.x;
				cy += s.y;
				nn++;
			}
		}
		if (nn == 0) return;
		cx /= nn;
		cy /= nn;
		float lag = std::hypot(cx - q.ax, cy - q.ay);
		float sp = q.contact_t > 0.0f ? 0.0f : (lag > 80.0f ? 0.0f : 30.0f);
		if (sp <= 0.0f) return;
		V2 w = q.path[q.pi];
		float dx = w.x - q.ax, dy = w.y - q.ay, d = std::hypot(dx, dy);
		if (d < 8.0f) {
			q.pi++;
			return;
		}
		q.hx = dx / d;
		q.hy = dy / d;
		q.ax += q.hx * sp * dt;
		q.ay += q.hy * sp * dt;
	}

	// выстрел из ПТ-оружия: настоящий снаряд с навесом и упреждением
	void inf_at_fire(int k, int ti) {
		Core::Soldier &s = c->inf[k];
		const Core::InfSquad &q = c->isq[s.squad];
		float v0 = s.role == IR_ATR ? 2200.0f : (s.role == IR_TUBE ? 430.0f : 300.0f);
		float sig = (s.role == IR_ATR ? 0.006f : (s.role == IR_TUBE ? 0.022f : 0.032f)) * (1.0f + s.sup * 1.5f);
		V3 mz = { s.x + std::cos(s.yaw) * 5.0f, inf_eye(s) - 1.0f, s.y + std::sin(s.yaw) * 5.0f };
		V3 tp = center(ti);
		float d0 = std::hypot(tp.x - mz.x, tp.z - mz.z);
		float tf = d0 / v0;
		tp.x += T(ti)[P_VX] * tf * 0.8f;
		tp.z += T(ti)[P_VY] * tf * 0.8f;
		float dxz = std::max(1.0f, std::hypot(tp.x - mz.x, tp.z - mz.z)), dy = tp.y - mz.y;
		float g = GRAVITY, v2 = v0 * v0;
		float disc = v2 * v2 - g * (g * dxz * dxz + 2.0f * dy * v2);
		float th = disc > 0.0f ? std::atan((v2 - std::sqrt(disc)) / (g * dxz)) : 0.6f;
		float yaw = std::atan2(tp.z - mz.z, tp.x - mz.x) + randn() * sig;
		th += randn() * sig;
		V3 dir = { std::cos(th) * std::cos(yaw), std::sin(th), std::cos(th) * std::sin(yaw) };
		int slot = c->w.shell_slot;
		c->w.shell_slot = (slot + 1) % 64;
		Core::Shell sh;
		sh.pos = mz;
		sh.vel = v3mul(dir, v0);
		sh.dist = 0.0f;
		sh.rico = 0;
		sh.owner = -1;
		sh.team = s.team;
		sh.slot = slot;
		if (s.role == IR_ATR) {
			sh.kind = AM_AP;
			sh.cal = 14.5f;
			sh.pen = q.atr_pen;
			sh.dmg = 24.0f;
			sh.he = 0.0f;
			s.rl = rnd(3.5f, 5.0f);
		} else {
			sh.kind = AM_HEAT;
			sh.cal = s.role == IR_TUBE ? q.tube_cal : 100.0f;
			sh.pen = s.role == IR_TUBE ? q.tube_pen : q.faust_pen;
			sh.dmg = s.role == IR_TUBE ? 110.0f : 130.0f;
			sh.he = 0.0f;
			s.rl = s.role == IR_TUBE ? rnd(8.0f, 11.0f) : 3.0f;
			s.ammo--;
		}
		if (c->shells.size() < 512) c->shells.push_back(sh);
		s.fired_t = 0.0f;
		s.aim_t = 0.0f;
		ev.add({ (float)W_INF_SHOT, (float)s.role, mz.x, mz.y, mz.z, dir.x, dir.y, dir.z, (float)slot, v0, (float)k });
	}

	// огонь из стрелкового оружия по бойцу
	void inf_small_fire(int k, int oi) {
		Core::Soldier &s = c->inf[k];
		Core::Soldier &o = c->inf[oi];
		bool smg = s.role == IR_SMG;
		float R = smg ? 270.0f : 540.0f;
		float d = std::hypot(o.x - s.x, o.y - s.y);
		float base = smg ? 0.36f : (s.role == IR_RIFLE ? 0.26f : 0.16f);
		float p = base * (1.0f - 0.65f * std::min(1.0f, d / R)) * inf_cover_k(o) * (1.0f - 0.6f * s.sup);
		s.rl = smg ? rnd(1.1f, 2.2f) : rnd(2.2f, 4.0f);
		s.fired_t = 0.0f;
		V3 a = { s.x + std::cos(s.yaw) * 4.0f, inf_eye(s) - 1.0f, s.y + std::sin(s.yaw) * 4.0f };
		V3 b = { o.x + rnd(-3.0f, 3.0f), inf_chest(o) + rnd(-1.0f, 3.0f), o.y + rnd(-3.0f, 3.0f) };
		V3 dir = v3norm(v3sub(b, a));
		ev.add({ (float)W_INF_SHOT, (float)s.role, a.x, a.y, a.z, dir.x, dir.y, dir.z, -1.0f, d, (float)k });
		if (randf() < p) {
			inf_kill(oi, -1, 0);
		} else {
			o.sup = std::min(1.0f, o.sup + (smg ? 0.3f : 0.22f));
			inf_suppress(o.x, o.y, 22.0f, 0.08f, o.team);
		}
	}

	// связка гранат под танк вплотную
	void inf_grenade(int k) {
		Core::Soldier &s = c->inf[k];
		int ti = s.throw_at;
		s.throw_at = -1;
		if (ti < 0 || ti >= n() || !c->td[ti].alive) return;
		float *t = T(ti);
		if (std::hypot(t[P_X] - s.x, t[P_Y] - s.y) > 75.0f) return;
		Core::TankDyn &d = c->td[ti];
		V3 at = { t[P_X] + rnd(-6.0f, 6.0f), t[P_GROUND] + 2.0f, t[P_Y] + rnd(-6.0f, 6.0f) };
		ev.add({ (float)W_INF_SHOT, 6.0f, at.x, at.y, at.z, 0.0f, 1.0f, 0.0f, -1.0f, 0.0f, (float)k });
		float r = randf();
		if (r < 0.45f) {
			bool fresh = d.track_broken <= 0.0f;
			if (fresh) c->w.stat[5]++;
			d.track_broken = TRACK_REPAIR;
			t[P_VX] *= 0.3f;
			t[P_VY] *= 0.3f;
			ev.add({ (float)EV_TRACK, (float)ti, -1.0f, at.x, at.y, at.z, fresh ? 1.0f : 0.0f });
		} else if (r < 0.6f) {
			int was, now;
			hit_module(ti, MOD_ENGINE, 45.0f, was, now);
			update(ti, -1, 0);
		}
		if (s.team == 0 && team(ti) == 1) d.lit = std::max(d.lit, 2.0f);
	}

	// что видит боец и кого выбирает целью
	void inf_think(int k) {
		Core::Soldier &s = c->inf[k];
		Core::InfSquad &q = c->isq[s.squad];
		s.think_t = rnd(0.35f, 0.6f);
		V3 eye = { s.x, inf_eye(s), s.y };
		// пехота противника: до трёх ближайших проверяем лучом
		int cand[3] = { -1, -1, -1 };
		float cd[3] = { 1e9f, 1e9f, 1e9f };
		for (size_t j = 0; j < c->inf.size(); j++) {
			const Core::Soldier &o = c->inf[j];
			if (!o.alive || o.team == s.team) continue;
			float d = std::hypot(o.x - s.x, o.y - s.y);
			if (d > inf_vis_range(o)) continue;
			for (int m = 0; m < 3; m++) {
				if (d < cd[m]) {
					for (int z = 2; z > m; z--) {
						cd[z] = cd[z - 1];
						cand[z] = cand[z - 1];
					}
					cd[m] = d;
					cand[m] = (int)j;
					break;
				}
			}
		}
		s.tgt_s = -1;
		float wr = s.role == IR_SMG ? 270.0f : 540.0f;
		for (int m = 0; m < 3; m++) {
			if (cand[m] < 0) break;
			Core::Soldier &o = c->inf[cand[m]];
			V3 tp = { o.x, inf_chest(o), o.y };
			if (!c->los(eye, tp) || c->smoke_blocks(eye, tp)) continue;
			o.seen[s.team] = 1.6f;
			if (s.tgt_s < 0 && cd[m] < wr) s.tgt_s = cand[m];
			if (cd[m] < 600.0f) q.contact_t = std::max(q.contact_t, 4.0f);
		}
		// танки противника
		s.tgt_t = -1;
		float at_r = s.role == IR_ATR ? 620.0f : (s.role == IR_TUBE ? 430.0f : (s.role == IR_FAUST ? 250.0f : 0.0f));
		if (s.ammo <= 0 && s.role != IR_ATR) at_r = 0.0f;
		float bd = 1e9f;
		int near_t = -1;
		for (int i = 0; i < n(); i++) {
			if (!c->td[i].alive || team(i) == s.team) continue;
			float d = std::hypot(T(i)[P_X] - s.x, T(i)[P_Y] - s.y);
			if (d > 650.0f) continue;
			V3 tc = center(i);
			if (!c->los(eye, tc) || c->smoke_blocks(eye, tc)) continue;
			if (d < 460.0f) c->td[i].lit = std::max(c->td[i].lit, 1.2f);
			if (d < 380.0f || d < at_r) q.contact_t = std::max(q.contact_t, 5.0f);
			if (d < bd) {
				bd = d;
				near_t = i;
			}
		}
		if (near_t >= 0 && bd < at_r) s.tgt_t = near_t;
		if (near_t >= 0 && bd < 60.0f && s.gren_cd <= 0.0f && s.sup < 0.7f && s.throw_t <= 0.0f && std::fabs(T(near_t)[P_SP]) < 45.0f) {
			s.throw_t = 0.9f;
			s.throw_at = near_t;
			s.gren_cd = rnd(10.0f, 16.0f);
		}
		// укрытие на время боя
		bool engaged = q.contact_t > 0.0f || s.sup > 0.2f;
		if (engaged && !s.has_cover) {
			V2 out;
			V2 p = { s.x, s.y };
			if (c->cover_near(p, 75.0f, out) || c->bush_near(p, 75.0f, -1, out)) {
				s.cx = out.x + rnd(-6.0f, 6.0f);
				s.cy = out.y + rnd(-6.0f, 6.0f);
			} else {
				s.cx = s.x;
				s.cy = s.y;
			}
			s.has_cover = true;
		} else if (!engaged) {
			s.has_cover = false;
		}
	}

	// ПТ-пушка: стоит на месте, расчёт разворачивает её на цель и бьёт бронебойным
	void inf_gun(int k) {
		Core::Soldier &s = c->inf[k];
		const Core::InfSquad &q = c->isq[s.squad];
		s.rl = std::max(0.0f, s.rl - dt);
		s.sup = std::max(0.0f, s.sup - dt * 0.2f);
		s.fired_t += dt;
		s.seen[0] = std::max(0.0f, s.seen[0] - dt);
		s.seen[1] = std::max(0.0f, s.seen[1] - dt);
		s.think_t -= dt;
		V3 eye = { s.x, s.gh + 9.0f, s.y };
		if (s.think_t <= 0.0f) {
			s.think_t = rnd(0.4f, 0.6f);
			float bd = 1e9f;
			s.tgt_t = -1;
			for (int i = 0; i < n(); i++) {
				if (!c->td[i].alive || team(i) == s.team) continue;
				float d = std::hypot(T(i)[P_X] - s.x, T(i)[P_Y] - s.y);
				if (d > 1000.0f) continue;
				// засада: издалека бьёт только по тем, кого уже видят свои, вблизи — по всем
				bool known = d < 520.0f || T(i)[s.team == 0 ? P_VIS0 : P_VIS1] != 0.0f;
				if (!known) continue;
				V3 tc = center(i);
				if (!c->los(eye, tc) || c->smoke_blocks(eye, tc)) continue;
				if (d < 480.0f) c->td[i].lit = std::max(c->td[i].lit, 1.2f);
				// из двух целей — та, что ближе к направлению ствола
				float score = d + std::fabs(ang_diff(std::atan2(T(i)[P_Y] - s.y, T(i)[P_X] - s.x), s.yaw)) * 200.0f;
				if (score < bd) {
					bd = score;
					s.tgt_t = i;
				}
			}
		}
		s.state = IS_STAND;
		if (s.tgt_t < 0 || !c->td[s.tgt_t].alive) {
			s.aim_t = 0.0f;
			return;
		}
		int ti = s.tgt_t;
		float v0 = std::max(600.0f, q.tube_pen);
		V3 mz = { s.x + std::cos(s.yaw) * 16.0f, s.gh + 8.5f, s.y + std::sin(s.yaw) * 16.0f };
		V3 tp = center(ti);
		float tf = std::hypot(tp.x - mz.x, tp.z - mz.z) / v0;
		tp.x += T(ti)[P_VX] * tf;
		tp.z += T(ti)[P_VY] * tf;
		float face = std::atan2(tp.z - s.y, tp.x - s.x);
		s.yaw = turn_toward(s.yaw, face, 0.5f * dt * (1.0f - 0.5f * s.sup));
		if (std::fabs(ang_diff(face, s.yaw)) > 0.02f) {
			s.aim_t = 0.0f;
			return;
		}
		s.aim_t += dt;
		if (s.rl > 0.0f || s.aim_t < 0.8f || s.sup > 0.8f) return;
		float dxz = std::max(1.0f, std::hypot(tp.x - mz.x, tp.z - mz.z)), dy = tp.y - mz.y;
		float g = GRAVITY, v2 = v0 * v0;
		float disc = v2 * v2 - g * (g * dxz * dxz + 2.0f * dy * v2);
		float th = disc > 0.0f ? std::atan((v2 - std::sqrt(disc)) / (g * dxz)) : 0.3f;
		float sig = 0.004f * (1.0f + s.sup * 2.0f);
		float yaw = std::atan2(tp.z - mz.z, tp.x - mz.x) + randn() * sig;
		th += randn() * sig;
		V3 dir = { std::cos(th) * std::cos(yaw), std::sin(th), std::cos(th) * std::sin(yaw) };
		int slot = c->w.shell_slot;
		c->w.shell_slot = (slot + 1) % 64;
		Core::Shell sh;
		sh.pos = mz;
		sh.vel = v3mul(dir, v0);
		sh.dist = 0.0f;
		sh.rico = 0;
		sh.owner = -1;
		sh.team = s.team;
		sh.slot = slot;
		sh.kind = AM_AP;
		sh.cal = q.tube_cal;
		sh.pen = q.atr_pen;
		sh.dmg = q.tube_cal * 1.7f;
		sh.he = q.tube_cal > 70.0f ? 60.0f : 0.0f;
		if (c->shells.size() < 512) c->shells.push_back(sh);
		float crew_k = s.ammo >= 3 ? 1.0f : (s.ammo == 2 ? 1.4f : 2.2f);
		s.rl = (q.tube_cal > 70.0f ? rnd(5.5f, 7.0f) : rnd(3.5f, 4.8f)) * crew_k;
		s.fired_t = 0.0f;
		s.aim_t = 0.3f;
		ev.add({ (float)W_INF_SHOT, 7.0f, mz.x, mz.y, mz.z, dir.x, dir.y, dir.z, (float)slot, v0, (float)k, q.tube_cal });
	}

	void inf_soldier(int k) {
		Core::Soldier &s = c->inf[k];
		if (!s.alive) {
			s.dead_t += dt;
			return;
		}
		if (s.role == IR_GUN) {
			// давят только чужие танки
			for (int i = 0; i < n(); i++) {
				const float *t = T(i);
				if (!c->td[i].alive || team(i) == s.team || std::fabs(t[P_SP]) < 10.0f) continue;
				if (std::hypot(s.x - t[P_X], s.y - t[P_Y]) < c->ds[i].W * 0.5f + 6.0f) {
					inf_kill(k, i, 2);
					return;
				}
			}
			inf_gun(k);
			return;
		}
		Core::InfSquad &q = c->isq[s.squad];
		s.rl = std::max(0.0f, s.rl - dt);
		s.sup = std::max(0.0f, s.sup - dt * 0.22f);
		s.gren_cd = std::max(0.0f, s.gren_cd - dt);
		s.fired_t += dt;
		s.seen[0] = std::max(0.0f, s.seen[0] - dt);
		s.seen[1] = std::max(0.0f, s.seen[1] - dt);
		s.think_t -= dt;
		if (s.think_t <= 0.0f) inf_think(k);
		// танки рядом: давят (чужие и быстрые свои), остальные расталкивают
		for (int i = 0; i < n(); i++) {
			const float *t = T(i);
			float dx = s.x - t[P_X], dy = s.y - t[P_Y];
			float reach = c->ds[i].L * 0.5f + 6.0f;
			if (dx * dx + dy * dy > reach * reach) continue;
			float ch = std::cos(t[P_HULL]), sh = std::sin(t[P_HULL]);
			float lx = dx * ch + dy * sh, ly = -dx * sh + dy * ch;
			float hl = c->ds[i].L * 0.5f + 1.5f, hw = c->ds[i].W * 0.5f + 1.5f;
			if (std::fabs(lx) > hl || std::fabs(ly) > hw) continue;
			float sp = std::fabs(t[P_SP]);
			if (c->td[i].alive && sp > 10.0f && team(i) != s.team) {
				inf_kill(k, i, 2);
				return;
			}
			float push = (ly >= 0.0f ? hw - ly : -hw - ly);
			s.x += -sh * push;
			s.y += ch * push;
		}
		// бросок гранаты
		if (s.throw_t > 0.0f) {
			s.throw_t -= dt;
			s.state = IS_THROW;
			s.anim = clampf(1.0f - s.throw_t / 0.9f, 0.0f, 1.0f);
			if (s.throw_at >= 0) s.yaw = std::atan2(T(s.throw_at)[P_Y] - s.y, T(s.throw_at)[P_X] - s.x);
			if (s.throw_t <= 0.35f && s.throw_at >= 0) inf_grenade(k);
			return;
		}
		bool engaged = q.contact_t > 0.0f || s.sup > 0.2f;
		float tx, ty;
		if (engaged) {
			tx = s.has_cover ? s.cx : s.x;
			ty = s.has_cover ? s.cy : s.y;
		} else {
			tx = q.ax + (-q.hy) * s.ox + q.hx * s.oy;
			ty = q.ay + q.hx * s.ox + q.hy * s.oy;
		}
		float dx = tx - s.x, dy = ty - s.y, d = std::hypot(dx, dy);
		bool pinned = s.sup > 0.75f;
		if (d > (s.still_t > 0.0f ? 9.0f : 3.0f) && !pinned) {
			bool crawl = s.sup > 0.45f;
			float sp = crawl ? 7.5f : (engaged ? 32.0f : 27.0f);
			float step = std::min(d, sp * dt);
			float px = s.x + dx / d * step, py = s.y + dy / d * step;
			c->resolve(px, py, 2.5f);
			px = clampf(px, 20.0f, c->ws - 20.0f);
			py = clampf(py, 20.0f, c->ws - 20.0f);
			float moved = std::hypot(px - s.x, py - s.y);
			if (moved > 1e-4f) s.yaw = turn_toward(s.yaw, std::atan2(py - s.y, px - s.x), 9.0f * dt);
			s.x = px;
			s.y = py;
			s.state = crawl ? IS_CRAWL : IS_RUN;
			s.anim += moved / (crawl ? 10.0f : 24.0f);
			s.still_t = 0.0f;
			s.aim_t = 0.0f;
			// упёрся в стену — укрытие здесь
			if (moved < step * 0.2f && engaged) {
				s.cx = s.x;
				s.cy = s.y;
			}
		} else {
			s.still_t += dt;
			float face = std::atan2(q.hy, q.hx);
			if (s.tgt_t >= 0 && c->td[s.tgt_t].alive) {
				face = std::atan2(T(s.tgt_t)[P_Y] - s.y, T(s.tgt_t)[P_X] - s.x);
			} else if (s.tgt_s >= 0 && c->inf[s.tgt_s].alive) {
				face = std::atan2(c->inf[s.tgt_s].y - s.y, c->inf[s.tgt_s].x - s.x);
			}
			s.yaw = turn_toward(s.yaw, face, 6.0f * dt);
			if (engaged) {
				bool low = s.sup > 0.3f || (!c->in_bush(s.x, s.y) && !c->covered({ s.x, s.y }));
				if (s.role == IR_TUBE || s.role == IR_FAUST) low = s.sup > 0.5f;
				s.state = low ? IS_PRONE : IS_KNEEL;
			} else {
				s.state = (q.hold || c->hold_team[s.team]) ? IS_CROUCH : IS_STAND;
			}
			if (s.still_t > 0.5f && s.rl <= 0.0f && s.sup < 0.85f) {
				if (s.tgt_t >= 0 && c->td[s.tgt_t].alive) {
					s.aim_t += dt;
					if (s.aim_t > (s.role == IR_ATR ? 0.9f : 1.5f) && std::fabs(ang_diff(face, s.yaw)) < 0.15f) inf_at_fire(k, s.tgt_t);
				} else if (s.tgt_s >= 0 && c->inf[s.tgt_s].alive) {
					if (std::fabs(ang_diff(face, s.yaw)) < 0.3f) inf_small_fire(k, s.tgt_s);
				}
			}
		}
		s.gh = c->height(s.x, s.y);
	}

	// пулемёты танков по пехоте: спаренный — куда смотрит башня, курсовой — вперёд, вблизи — любой
	void inf_mg(int i) {
		const Core::TankDyn &d = c->td[i];
		if (!d.alive || !d.gun_crew) return;
		float *t = T(i);
		V3 eye = top(i);
		int best = -1;
		float bd = 1e9f, bp = 0.0f;
		for (size_t j = 0; j < c->inf.size(); j++) {
			Core::Soldier &o = c->inf[j];
			if (!o.alive || o.team == team(i)) continue;
			float dx = o.x - t[P_X], dy = o.y - t[P_Y], dist = std::hypot(dx, dy);
			if (dist > inf_vis_range(o) * 0.9f || dist > 620.0f) continue;
			V3 tp = { o.x, inf_chest(o), o.y };
			if (!c->los(eye, tp) || c->smoke_blocks(eye, tp)) continue;
			o.seen[team(i)] = 1.6f;
			float br = std::atan2(dy, dx);
			float p = 0.0f;
			if (std::fabs(ang_diff(br, t[P_TUR])) < 0.32f) {
				p = 0.3f;
			} else if (std::fabs(ang_diff(br, t[P_HULL])) < 0.6f && dist < 420.0f) {
				p = 0.2f;
			} else if (dist < 260.0f) {
				p = 0.12f;
			}
			if (p > 0.0f && dist < bd) {
				bd = dist;
				best = (int)j;
				bp = p;
			}
		}
		if (best < 0) return;
		Core::Soldier &o = c->inf[best];
		V3 b = { o.x + rnd(-4.0f, 4.0f), inf_chest(o) + rnd(-1.0f, 2.0f), o.y + rnd(-4.0f, 4.0f) };
		V3 dir = v3norm(v3sub(b, eye));
		ev.add({ (float)W_INF_SHOT, 5.0f, eye.x, eye.y, eye.z, dir.x, dir.y, dir.z, -1.0f, bd, (float)i });
		float p = bp * (1.0f - 0.6f * bd / 620.0f) * inf_cover_k(o);
		if (randf() < p) {
			inf_kill(best, i, 0);
		} else {
			o.sup = std::min(1.0f, o.sup + 0.4f);
			inf_suppress(o.x, o.y, 26.0f, 0.2f, o.team);
		}
	}

	void inf_step() {
		if (c->inf.empty()) return;
		c->inf_t -= dt;
		bool tick = c->inf_t <= 0.0f;
		if (tick) c->inf_t = 1.0f;
		for (int qi = 0; qi < (int)c->isq.size(); qi++) {
			if (tick) inf_squad_plan(qi);
			inf_squad_move(qi);
		}
		for (int k = 0; k < (int)c->inf.size(); k++) inf_soldier(k);
		if (c->mg_t.size() != (size_t)n()) c->mg_t.assign(n(), 0.0f);
		for (int i = 0; i < n(); i++) {
			c->mg_t[i] -= dt;
			if (c->mg_t[i] > 0.0f) continue;
			c->mg_t[i] = rnd(0.3f, 0.45f);
			inf_mg(i);
		}
	}

	// разрывы снарядов этого шага — по пехоте
	void inf_shell_blasts() {
		for (Core::Shell &s : c->shells) {
			if (!s.dead || s.boom == 0) continue;
			if (s.kind != AM_SMOKE && !c->inf.empty()) inf_blast(s.hit_pos, s.cal, s.kind == AM_HE ? std::max(s.he, 1.0f) : 0.0f, s.owner);
			if (s.kind == AM_HE && s.boom == 1 && s.cal >= 100.0f) blast_tanks(s);
			s.boom = 0;
		}
	}

	// ---------- удары: артиллерия и штурмовик ----------
	void strike_shell(const Core::Strike &k, float tx, float tz) {
		float gh = c->height(tx, tz);
		float fall = k.kind == 0 ? 760.0f : 380.0f, fwd = k.kind == 0 ? 150.0f : 330.0f, H = k.kind == 0 ? 520.0f : 210.0f;
		float tf = (-fall + std::sqrt(fall * fall + 2.0f * GRAVITY * H)) / GRAVITY;
		Core::Shell sh;
		sh.pos = { tx - k.dx * fwd * tf, gh + H, tz - k.dz * fwd * tf };
		sh.vel = { k.dx * fwd, -fall, k.dz * fwd };
		sh.dist = 0.0f;
		sh.rico = 0;
		sh.owner = k.by;
		sh.team = k.team;
		sh.kind = AM_HE;
		sh.cal = k.cal;
		sh.he = k.kind == 0 ? 3600.0f : 15000.0f;
		sh.dmg = k.kind == 0 ? 320.0f : 600.0f;
		sh.pen = k.kind == 0 ? 35.0f : 70.0f;
		int slot = c->w.shell_slot;
		c->w.shell_slot = (slot + 1) % 64;
		sh.slot = slot;
		if (c->shells.size() < 512) c->shells.push_back(sh);
		V3 dir = v3norm(sh.vel);
		ev.add({ (float)W_INF_SHOT, 8.0f, sh.pos.x, sh.pos.y, sh.pos.z, dir.x, dir.y, dir.z, (float)slot, v3len(sh.vel), -1.0f, k.cal });
	}

	bool strike_add(int kind, int team, float x, float z, int by) {
		if (c->strikes.size() >= 6 || !std::isfinite(x) || !std::isfinite(z)) return false;
		Core::Strike k;
		k.kind = kind != 0 ? 1 : 0;
		k.team = team != 0 ? 1 : 0;
		k.by = by;
		k.x = clampf(x, 30.0f, c->ws - 30.0f);
		k.z = clampf(z, 30.0f, c->ws - 30.0f);
		k.t = k.kind == 0 ? 5.0f : 6.5f;
		k.left = k.kind == 0 ? 8 : 4;
		k.cal = k.kind == 0 ? 122.0f : 150.0f;
		float ax = rnd(-0.35f, 0.35f), az = k.team == 0 ? -1.0f : 1.0f, al = std::hypot(ax, az);
		k.dx = ax / al;
		k.dz = az / al;
		c->strikes.push_back(k);
		return true;
	}

	// бот-командир: удар по скоплению врага, которое видит команда; рядом со своими не бьёт
	bool bot_strike(int tm) {
		int best = -1;
		float bs = 1.4f;
		for (int i = 0; i < n(); i++) {
			if (!c->td[i].alive || team(i) == tm) continue;
			if (T(i)[tm == 0 ? P_VIS0 : P_VIS1] == 0.0f) continue;
			if (std::fabs(T(i)[P_SP]) > 35.0f) continue;
			float sc = 1.0f;
			bool own = false;
			for (int j = 0; j < n(); j++) {
				if (j == i || !c->td[j].alive) continue;
				float d = std::hypot(T(j)[P_X] - T(i)[P_X], T(j)[P_Y] - T(i)[P_Y]);
				if (team(j) == tm) {
					own = own || d < 190.0f;
				} else if (d < 150.0f) {
					sc += 1.0f;
				}
			}
			for (const Core::Soldier &s : c->inf) {
				if (!s.alive) continue;
				float d = std::hypot(s.x - T(i)[P_X], s.y - T(i)[P_Y]);
				if (s.team == tm) {
					own = own || d < 150.0f;
				} else if (d < 120.0f && s.seen[tm] > 0.0f) {
					sc += 0.25f;
				}
			}
			if (std::fabs(T(i)[P_SP]) < 3.0f) sc += 0.5f;
			if (!own && sc > bs) {
				bs = sc;
				best = i;
			}
		}
		if (best < 0) return false;
		return strike_add(randf() < 0.35f ? 1 : 0, tm, T(best)[P_X] + rnd(-25.0f, 25.0f), T(best)[P_Y] + rnd(-25.0f, 25.0f), -1);
	}

	void strikes_step() {
		for (Core::Strike &k : c->strikes) {
			if (!k.told) {
				k.told = true;
				ev.add({ (float)W_STRIKE, (float)k.kind, (float)k.team, k.x, k.z, k.t, k.dx, k.dz, (float)k.by });
			}
			k.t -= dt;
			if (k.t > 0.0f || k.left <= 0) continue;
			k.next -= dt;
			while (k.next <= 0.0f && k.left > 0) {
				if (k.kind == 0) {
					float r = 80.0f * std::sqrt(randf()), a = randf() * 2.0f * PI_F;
					strike_shell(k, k.x + std::cos(a) * r, k.z + std::sin(a) * r);
					k.next += rnd(0.25f, 0.55f);
				} else {
					float off = ((float)(4 - k.left) - 1.5f) * 50.0f;
					strike_shell(k, k.x + k.dx * off + rnd(-10.0f, 10.0f), k.z + k.dz * off + rnd(-10.0f, 10.0f));
					k.next += 0.15f;
				}
				k.left--;
			}
		}
		c->strikes.erase(std::remove_if(c->strikes.begin(), c->strikes.end(), [](const Core::Strike &k) { return k.left <= 0; }), c->strikes.end());
		if (c->strike_ai && !c->w.over) {
			for (int tm = 0; tm < 2; tm++) {
				c->strike_t[tm] -= dt;
				if (c->strike_t[tm] > 0.0f) continue;
				c->strike_t[tm] = bot_strike(tm) ? rnd(100.0f, 150.0f) : 8.0f;
			}
		}
	}

	// близкий разрыв тяжёлого фугаса или бомбы: танку рвёт гусеницу, бывает — глушит двигатель
	void blast_tanks(const Core::Shell &s) {
		float R = c->upm * s.cal * 0.024f;
		for (int i = 0; i < n(); i++) {
			if (!c->td[i].alive || team(i) == (s.owner >= 0 ? team(s.owner) : s.team)) continue;
			float *t = T(i);
			float d = std::hypot(t[P_X] - s.hit_pos.x, t[P_Y] - s.hit_pos.z);
			if (d > R + c->ds[i].W * 0.5f) continue;
			Core::TankDyn &td = c->td[i];
			float r = randf();
			if (r < 0.55f) {
				bool fresh = td.track_broken <= 0.0f;
				if (fresh) c->w.stat[5]++;
				td.track_broken = TRACK_REPAIR;
				t[P_VX] *= 0.3f;
				t[P_VY] *= 0.3f;
				ev.add({ (float)EV_TRACK, (float)i, (float)s.owner, t[P_X], t[P_GROUND] + 3.0f, t[P_Y], fresh ? 1.0f : 0.0f });
			} else if (r < 0.8f) {
				int was, now;
				hit_module(i, s.cal >= 140.0f ? MOD_ENGINE : MOD_OPTICS, 45.0f, was, now);
				update(i, s.owner, 0);
			}
			if (team(i) == 1) td.lit = std::max(td.lit, 2.0f);
		}
	}
