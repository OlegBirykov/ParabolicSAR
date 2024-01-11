----------------------------------------------------------------------------------
----- Робот для торговли на срочном рынке на основе индикатора Parabolic SAR ----- 
----------------------------------- Версия 1.0 -----------------------------------
----------------------------------------------------------------------------------

dofile(getScriptPath() .. '\\library.lua');

logFileName = getScriptPath() .. '\\log.txt';   -- имя файла журнала
isRun = true;                                   -- работает основной цикл скрипта
timer = 3;                                      -- обратный счётчик таймера в секундах                                  
err = '';                                       -- сообщение об ошибке
nowPos = 0;                                     -- текущая позиция по инструменту
prevPos = 0;                                    -- позиция на предыдущем шаге

class = 'SPBFUT';                               -- срочный рынок
emit = 'SiH4';                                  -- код инструмента (фьючерс US-RU до марта 2024)
account = 'A728crz';                            -- счёт клиента
sarId = 'SAR_SI';                               -- id графика Parabolic SAR
priceId = 'PRICE_SI';                           -- id графика цены
lot = 1;                                        -- размер позиции в лотах
risk = 1;                                       -- размер остатка позиции после быстрого профита, остающийся до следующего сигнала по SAR
spread = 50;                                    -- защитный спред при выставлении лимитной заявки в шагах цены

-- параметры стандартной стоп-заявки, устанавливаемой на случай потери связи с сервером
profit = 1000;                                  -- размер тейк-профита в шагах цены
offset = 0;                                     -- размер отступа тейк-профита в шагах цены                          
stop = 500;                                     -- размер стоп-лимита в шагах цены

-- параметры ручных стоп-сигналов, дополняющих сигналы от SAR
referenceLevel = 0;                             -- опорный уровень (цена открытия позиции)
quickProfit = 100;                              -- смещение для быстрого профита в валюте цены (частичное закрытие позиции, остаётся risk лотов)
quickStop = 10;                                 -- смещение для быстрого стопа в валюте цены (полное закрытие позиции)
correctOffset = 200;                            -- смещение для коррекции опорного уровня на величину quickStop при росте позиции 

-- параметры фильтра ложных сигналов от SAR
triggerSignal = 0;                              -- 0 - нет сигнала или сигнал подтверждён 
                                                -- 1 - неподтверждённый сигнал на открытие длинной позиции
                                                -- -1 - неподтверждённый сигнал на открытие короткой позиции
triggerLevel = 0;                               -- уровень цены, достижение которого подтверждает сигнал от SAR
triggerOffset = 10;                             -- смещение относительно последнего значения SAR до разрыва графика,
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
    
    message('Program "Parabolic SAR 1.0" started', 1);
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
