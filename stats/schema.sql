-- Prime Era · Статистика постов: таблицы для MySQL 8.4
-- Импорт: phpMyAdmin → база cq300982_1 → вкладка «Импорт» → выбрать этот файл.
-- Все таблицы с префиксом stat_, чтобы не пересекаться с тем, что уже лежит в базе.

SET NAMES utf8mb4;

-- Общие настройки компании (окончание отчётной недели и т. п.)
CREATE TABLE IF NOT EXISTS stat_settings (
  name        VARCHAR(64)  NOT NULL PRIMARY KEY,
  value       VARCHAR(255) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Отделы
CREATE TABLE IF NOT EXISTS stat_departments (
  id          VARCHAR(40)  NOT NULL PRIMARY KEY,
  name        VARCHAR(200) NOT NULL,
  created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Статистики отдела: шаблон, который получает каждый сотрудник отдела
CREATE TABLE IF NOT EXISTS stat_metrics (
  department_id VARCHAR(40)  NOT NULL,
  id            VARCHAR(40)  NOT NULL,
  name          VARCHAR(200) NOT NULL,
  unit          VARCHAR(20)  NOT NULL DEFAULT '',
  period        ENUM('day','week','month') NOT NULL DEFAULT 'week',
  agg           ENUM('sum','avg')          NOT NULL DEFAULT 'sum',   -- как считать общий график отдела
  inverse       TINYINT(1)   NOT NULL DEFAULT 0,                    -- 1 = чем меньше, тем лучше
  target        DECIMAL(18,2) NULL,                                 -- план отдела
  emp_target    DECIMAL(18,2) NULL,                                 -- план на сотрудника
  sort          INT          NOT NULL DEFAULT 0,
  PRIMARY KEY (department_id, id),
  CONSTRAINT fk_metric_dept FOREIGN KEY (department_id) REFERENCES stat_departments(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Сотрудники
CREATE TABLE IF NOT EXISTS stat_employees (
  id            VARCHAR(40)  NOT NULL PRIMARY KEY,
  department_id VARCHAR(40)  NULL,
  name          VARCHAR(200) NOT NULL,
  post          VARCHAR(200) NOT NULL DEFAULT '',                   -- пост (должность)
  created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY ix_emp_dept (department_id),
  CONSTRAINT fk_emp_dept FOREIGN KEY (department_id) REFERENCES stat_departments(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Статистики сотрудника. metric_id заполнен — статистика отдела, NULL — личная.
CREATE TABLE IF NOT EXISTS stat_statistics (
  id            VARCHAR(40)  NOT NULL PRIMARY KEY,
  employee_id   VARCHAR(40)  NOT NULL,
  metric_id     VARCHAR(40)  NULL,
  name          VARCHAR(200) NOT NULL,
  unit          VARCHAR(20)  NOT NULL DEFAULT '',
  period        ENUM('day','week','month') NOT NULL DEFAULT 'week',
  inverse       TINYINT(1)   NOT NULL DEFAULT 0,
  target        DECIMAL(18,2) NULL,                                 -- личный план
  created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY ix_stat_emp (employee_id),
  CONSTRAINT fk_stat_emp FOREIGN KEY (employee_id) REFERENCES stat_employees(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Значения: одна строка = одна цифра за один период.
-- period_end — дата окончания периода (для недели — день окончания отчётной недели, для месяца — 1-е число).
CREATE TABLE IF NOT EXISTS stat_values (
  statistic_id  VARCHAR(40)   NOT NULL,
  period_end    DATE          NOT NULL,
  value         DECIMAL(18,2) NOT NULL,
  created_at    DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at    DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (statistic_id, period_end),
  KEY ix_val_period (period_end),
  CONSTRAINT fk_val_stat FOREIGN KEY (statistic_id) REFERENCES stat_statistics(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Плоский вид для отчётов и Excel: те же колонки, что у кнопки «Выгрузить таблицу CSV»
CREATE OR REPLACE VIEW stat_values_flat AS
SELECT v.period_end           AS `дата`,
       d.name                 AS `отдел`,
       e.name                 AS `сотрудник`,
       e.post                 AS `пост`,
       s.name                 AS `статистика`,
       s.unit                 AS `единица`,
       s.period               AS `период`,
       v.value                AS `значение`
FROM stat_values v
JOIN stat_statistics s ON s.id = v.statistic_id
JOIN stat_employees  e ON e.id = s.employee_id
LEFT JOIN stat_departments d ON d.id = e.department_id;

-- Итоги отдела по неделям (то, что дашборд рисует в строке «Весь отдел»)
CREATE OR REPLACE VIEW stat_department_totals AS
SELECT d.id AS department_id, d.name AS department, m.id AS metric_id, m.name AS metric, m.unit,
       v.period_end,
       CASE WHEN m.agg = 'avg' THEN ROUND(AVG(v.value), 2) ELSE SUM(v.value) END AS value,
       COUNT(*) AS employees_reported
FROM stat_values v
JOIN stat_statistics s ON s.id = v.statistic_id
JOIN stat_employees  e ON e.id = s.employee_id
JOIN stat_metrics    m ON m.department_id = e.department_id AND m.id = s.metric_id
JOIN stat_departments d ON d.id = e.department_id
GROUP BY d.id, d.name, m.id, m.name, m.unit, m.agg, v.period_end;

-- Текущая структура из дашборда (можно запускать повторно)
INSERT INTO stat_settings (name, value) VALUES ('week_end_day', '4'), ('week_end_time', '14:00')
  ON DUPLICATE KEY UPDATE value = VALUES(value);

INSERT INTO stat_departments (id, name) VALUES ('sales', 'Отдел продаж')
  ON DUPLICATE KEY UPDATE name = VALUES(name);

INSERT INTO stat_metrics (department_id, id, name, unit, period, agg, sort) VALUES
  ('sales', 'out',   'Исходящие', 'шт', 'week', 'sum', 1),
  ('sales', 'calls', 'Созвоны',   'шт', 'week', 'sum', 2),
  ('sales', 'rev',   'Доход',     '₽',  'week', 'sum', 3)
  ON DUPLICATE KEY UPDATE name = VALUES(name), unit = VALUES(unit);

INSERT INTO stat_employees (id, department_id, name, post) VALUES
  ('m1', 'sales', 'Менеджер 1', 'Менеджер по продажам'),
  ('m2', 'sales', 'Менеджер 2', 'Менеджер по продажам'),
  ('m3', 'sales', 'Менеджер 3', 'Менеджер по продажам')
  ON DUPLICATE KEY UPDATE name = VALUES(name), post = VALUES(post);

INSERT INTO stat_statistics (id, employee_id, metric_id, name, unit, period) VALUES
  ('m1-out', 'm1', 'out', 'Исходящие', 'шт', 'week'), ('m1-calls', 'm1', 'calls', 'Созвоны', 'шт', 'week'), ('m1-rev', 'm1', 'rev', 'Доход', '₽', 'week'),
  ('m2-out', 'm2', 'out', 'Исходящие', 'шт', 'week'), ('m2-calls', 'm2', 'calls', 'Созвоны', 'шт', 'week'), ('m2-rev', 'm2', 'rev', 'Доход', '₽', 'week'),
  ('m3-out', 'm3', 'out', 'Исходящие', 'шт', 'week'), ('m3-calls', 'm3', 'calls', 'Созвоны', 'шт', 'week'), ('m3-rev', 'm3', 'rev', 'Доход', '₽', 'week')
  ON DUPLICATE KEY UPDATE name = VALUES(name);
