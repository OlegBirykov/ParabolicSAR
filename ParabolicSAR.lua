----------------------------------------------------------------------------------
----- Робот для торговли на срочном рынке на основе индикатора Parabolic SAR ----- 
----------------------------------- Версия 1.2 -----------------------------------
----------------------------------------------------------------------------------

dofile(getScriptPath() .. '\\library.lua');

logFileName = getScriptPath() .. '\\log.txt';   -- имя файла журнала
isRun = true;                                   -- работает основной цикл скрипта
timer = 3;                                      -- обратный счётчик таймера в секундах                                  
err = '';                                       -- сообщение об ошибке
nowPos = 0;                                     -- текущая позиция по инструменту
prevPos = 0;                                    -- позиция на предыдущем шаге

class = 'SPBFUT';                               -- срочный рынок
emit = 'SiZ4';                                  -- код инструмента
account = 'A728crz';                            -- счёт клиента
sarId = 'SAR_SI';                               -- id графика Parabolic SAR
priceId = 'PRICE_SI';                           -- id графика цены
lot = 1;                                        -- размер позиции в лотах
spread = 50;                                    -- защитный спред при выставлении лимитной заявки в шагах цены
dealCounter = 3;                                -- счётчик для ограничения количества сделок

-- параметры стандартной стоп-заявки
profit = {20, 150};                             -- размер тейк-профита в шагах цены
offset = {50, 150};                             -- размер отступа тейк-профита в шагах цены
stop = {30, -50};                               -- размер стоп-лимита в шагах цены
phase = 1;                                      -- фаза стоп-заявки
phaseLevel = 150;                               -- уровень перехода к фазе 2


-- параметры фильтра ложных сигналов от SAR
triggerSignal = 0;                              -- 0 - нет сигнала или сигнал подтверждён 
                                                -- 1 - неподтверждённый сигнал на открытие длинной позиции
                                                -- -1 - неподтверждённый сигнал на открытие короткой позиции
triggerLevel = 0;                               -- уровень цены, достижение которого подтверждает сигнал от SAR
triggerOffset = 20;                             -- смещение относительно последнего значения SAR до разрыва графика,
                                                -- для формирования уровня triggerLevel
----------------------------------------------------------------------------------
--------------------------------- Запуск робота ----------------------------------
----------------------------------------------------------------------------------
function OnInit()
    -- создать и инициализировать таблицу
    tableId = AllocTable(); -- первое упоминание переменной в любом месте без ключевого слова local 
                            -- делает её глобальной
    AddColumn(tableId, 1, 'PARAMETER', true, QTABLE_STRING_TYPE, 20);
    AddColumn(tableId, 2, 'VALUE', true, QTABLE_STRING_TYPE, 20);
    AddColumn(tableId, 3, 'COMMENT', true, QTABLE_STRING_TYPE, 30); 
    CreateWindow(tableId);    
    putDataToTableInit();
    
    message('Program "Parabolic SAR 1.2" started', 1);
    writeToLogFile('Program started');
end

----------------------------------------------------------------------------------
----------------------------- Основной поток скрипта -----------------------------
-- Всё остальное выполняется в главном потоке приложения quik, вместе с командами
-- от интерфейса пользователя, а main выполняется в отдельном потоке. Поэтому 
-- длительные вычисления и sleep в обработчиках событий вешают весь quik.
-- Завершение функции main переводит скрипт в состояние "Остановлено", при этом
-- функции обработки событий данного скрипта больше не вызываются.
----------------------------------------------------------------------------------
function main()
    while (isRun) do
        body();
    end         
end

----------------------------------------------------------------------------------
------------------------------------- Сделка -------------------------------------
----------------------------------------------------------------------------------
function OnTrade(trade)
end

----------------------------------------------------------------------------------
------------------------------------- Заявка -------------------------------------
----------------------------------------------------------------------------------
function OnOrder(order)
end

----------------------------------------------------------------------------------
---------------------------------- Стоп-заявка -----------------------------------
----------------------------------------------------------------------------------
function OnStopOrder()
end

----------------------------------------------------------------------------------
--------------------------------- Останов робота ---------------------------------
----------------------------------------------------------------------------------
function OnStop()
    isRun = false;
    DestroyTable(tableId);
    writeToLogFile('Program stopped');
end
