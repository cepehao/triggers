--функция uuid_generate_v1mc из модуля uuid-ossp
CREATE OR REPLACE FUNCTION public.uuid_generate_v1mc()
    RETURNS uuid
    LANGUAGE 'c'
    COST 1
    VOLATILE STRICT PARALLEL SAFE 
AS '$libdir/uuid-ossp', 'uuid_generate_v1mc';
ALTER FUNCTION public.uuid_generate_v1mc()
    OWNER TO postgres;

--создаем тригерную функцию
CREATE OR REPLACE FUNCTION upd_spec_maxvalue()
RETURNS trigger AS
$$
DECLARE
    maxValue integer;
BEGIN
    EXECUTE format('select max(%s) from %s', tg_argv[1], tg_argv[0]) INTO maxValue;
    UPDATE spec
    SET cur_max_value = maxValue
    WHERE table_name = tg_argv[0] AND column_name = tg_argv[1] AND maxValue > cur_max_value;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

--наша хранимая процедура, в которую добавили создание тригера
CREATE OR REPLACE FUNCTION xp (_table_name text, _column_name text) 
RETURNS integer
AS $$
DECLARE
  maxValue integer := 0;
BEGIN
  IF 
  	(SELECT COUNT(*)
    FROM spec
	WHERE column_name = _column_name AND table_name = _table_name) > 0
  THEN 
    UPDATE spec
  	SET cur_max_value = cur_max_value + 1
  	WHERE column_name = _column_name AND table_name = _table_name;
	
  	RETURN cur_max_value FROM spec
		   WHERE column_name = _column_name AND table_name = _table_name;

  ELSE  
    EXECUTE format('SELECT MAX(%s) 
		           FROM %s ', 
				   _column_name, _table_name)
    				INTO maxValue;
	IF maxValue IS null THEN maxValue := 1; ELSE maxValue := maxValue + 1; END IF;
	
	EXECUTE format('INSERT INTO spec  
					VALUES (%s, ''%s'', ''%s'', %s)', 
				   (SELECT xp('spec', 'id')), _table_name, _column_name, maxValue); 

	--создания тригера на вставку
	EXECUTE format('CREATE TRIGGER %I AFTER INSERT ON %s                        
                        FOR EACH STATEMENT
                        EXECUTE FUNCTION upd_spec_maxvalue(%s, %s);',
        'spec_curmax_insert_'||_column_name||'_'||(SELECT uuid_generate_v1mc()), _table_name, _table_name, _column_name);
	
    --создание тригера на изменение
	EXECUTE format ('CREATE TRIGGER %I AFTER UPDATE ON %s                     
					FOR EACH STATEMENT
					EXECUTE FUNCTION upd_spec_maxvalue(%s, %s);',
	'spec_curmax_update_'||_column_name||'_'||(SELECT uuid_generate_v1mc()), _table_name, _table_name, _column_name);
	
	RETURN maxValue;
  END IF;
END;
$$ LANGUAGE plpgsql;

--создадим таблицу spec
CREATE TABLE spec
(
    id integer NOT NULL,
    table_name character varying(30) NOT NULL,
    column_name character varying(30) NOT NULL,
    cur_max_value integer NOT NULL
);
--добавим изначальные значения
INSERT INTO spec VALUES (1, 'spec', 'id', 1);
--создадим таблицу test
CREATE TABLE test
(
    id integer NOT NULL
);
--добавим в столбец id таблицы тест значение 30
INSERT INTO test VALUES (30)
--вызовем хранимую процедуру с параметрами test id
SELECT xp('test', 'id')
--посмотрим таблицу spec до добавления больших значений в таблицу test
SELECT * FROM spec
--добавим значение, больше максимального в id таблицы test
INSERT INTO test VALUES (100)
--проверим таблицу spec 
SELECT * FROM spec
--посмотрим таблицу test
SELECT * FROM test
--теперь попробуем изменить максимальный id в таблице test
UPDATE test
SET id = 200
WHERE id = (SELECT min(id) FROM TEST)
--таблица spec после изменения
SELECT * FROM spec
--таблица test после изменения
SELECT * FROM test
--попробуем уменьшить максимальный id в таблице test (200 изменится на 20)
UPDATE test
SET id = 20
WHERE id = (SELECT min(id) FROM TEST)
--проверяем, что cur_max_value у test в таблице spec не изменилась
SELECT * FROM spec 
--потестируем с таблицей, у которой более 1 стобца
--создадим таблицу test2 со столбцами max1 и max2
CREATE TABLE test2
(
    max1 integer NOT NULL,
	max2 integer NOT NULL
);
--добавим в test2 значения 5 и 10
INSERT INTO test2 VALUES (5, 10);
--вызовем хранимую процедуру с обоими столбцами
--и посмотрим корректно ли создались для них тригеры
SELECT xp('test2', 'max1')
SELECT xp('test2', 'max2')
--для каждого столбца создалось 2 триггера на изменения и добавление
--проверим их работоспособность (для начала добавим новую запись так,
--чтобы появился новый максимальный max1)
INSERT INTO test2 VALUES (50, 5);
--проверим таблицу spec
SELECT * FROM spec
--теперь обновим максимумы сразу в двух столбиках
INSERT INTO test2 VALUES (150, 200);
--и проверим таблицу spec
SELECT * FROM spec

