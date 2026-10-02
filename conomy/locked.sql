SHOW FULL PROCESSLIST;

SELECT CONCAT('KILL ', id, ';') AS kill_cmd,
       id,
       time   AS running_seconds,
       state,
       info   AS query
FROM information_schema.processlist
# WHERE user = 'brian'

ORDER BY time DESC;

SELECT CONCAT('KILL ', id, ';') AS kill_cmd,
       id,
       user,
       time AS running_seconds
FROM information_schema.processlist
WHERE command = 'Sleep'
  AND user = 'brian'          -- 특정 유저만
  -- AND time > 3600             -- n초 이상 슬립만
ORDER BY time DESC;

KILL 4277560;
KILL 4280280;
KILL 4282887;
KILL 4283810;
KILL 4283935;
KILL 4283806;
KILL 4283938;
KILL 4283846;
KILL 4283848;
KILL 4283811;
KILL 4284004;
KILL 4282694;
KILL 4283855;
KILL 4283830;
KILL 4283841;
KILL 4283845;
KILL 4286360;
KILL 4284736;
KILL 4286362;
KILL 4282888;
KILL 4283850;
KILL 4283843;
KILL 4283941;
KILL 4287004;
KILL 4287005;
KILL 4287007;
