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
  -- AND user = 'brian'          -- 특정 유저만
  -- AND time > 3600             -- n초 이상 슬립만
ORDER BY time DESC;

KILL 2504710;
KILL 2504859;
KILL 2504708;
KILL 2504692;
KILL 2504415;
KILL 2504595;
KILL 2504847;
KILL 2504832;
KILL 2502570;
KILL 2504553;
KILL 2504834;
KILL 2264925;
KILL 2505146;
KILL 2505221;
KILL 2264904;
KILL 2505222;
KILL 2504856;
KILL 2504419;
KILL 2504414;
KILL 2504550;
KILL 2504750;
KILL 2504967;
KILL 2504719;
KILL 2504417;
KILL 2504416;
KILL 2504894;
KILL 2504751;
KILL 2504513;
KILL 2504511;
KILL 2504344;
KILL 2505220;
KILL 2500361;
