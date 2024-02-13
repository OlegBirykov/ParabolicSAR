----------------------------------------------------------------------------------
-------------------------- Тело основного цикла скрипта --------------------------
----------------------------------------------------------------------------------
function body() 
    -- пока работает таймер, выводить в таблицу сообщение об ошибке и не делать больше ничего
    if (timer > 0) then
        timer = timer - 1;
        putDataToTableTimer();
        sleep(1000);
        return;
    end

    -- если не удаётся определить время сервера, вывести сообщение об отсутствии связи и ждать 3 секунды
    local serverTime = getInfoParam('SERVERTIME');
    if (serverTime == nil or serverTime == '') then
        err = 'No connect';
        timer = 3;
        return;
    else
        err = '';
    end

    -- если пользователь вручную закрыл окно таблицы, открыть таблицу заново
    if (IsWindowClosed(tableId)) then
        CreateWindow(tableId);    
        putDataToTableInit();    
    end

    -- если торговая сессия остановлена, вывести сообщение и ждать 3 секунды 
    local sessionStatus = tonumber(getParamEx(class, emit, 'STATUS').param_value);
    if (sessionStatus ~= 1) then 
        err = 'Session closed';
        timer = 3;
        return;
    end    

    -- обработчик событий таблицы
    local onTableEvent = function(tableId, msg, row, col)
        -- двойной щелчок левой кнопкой мыши
        if (msg == QTABLE_LBUTTONDBLCLK) then
            -- ячейка строка 13 столбец 1 - вывести тестовое сообщение
            if (row == 13 and col == 1) then
                message('Test message');
            end
            -- ячейка строка 13 столбец 3 - остановить робота
            if (row == 13 and col == 3) then
                isRun = false;
            end
        end
    end

    -- установить обработчик событий таблицы
    SetTableNotificationCallback(tableId, onTableEvent);

    -- если дошли досюда, сбросить сообщение об ошибке и вывести время сервера
    err = '';
    SetCell(tableId, 1, 2, serverTime);
    SetCell(tableId, 1, 3, err);

    -- счётчик транзакций
    local transCount = 0;

    -- найти текущую позицию по инструменту
    nowPos = getNowPos();

    -- если переворот или закрытие позиции, убрать прежние тейк-профиты
    if (nowPos == 0 or sign(nowPos) ~= sign(prevPos)) then
        -- здесь и далее такая конструкция автоматически положит программу, если функция вернёт nil
        transCount = transCount + deleteAllProfits('Remove take profit');
    end

    -- проверить наличие сигнала с графика и определить текущую цену
    local signal = signalCheck();

    -- если сигнал лонг или шорт, то купить или продать
    if (math.abs(signal) == 2) then
        local needPos = sign(signal) * lot;
        transCount = transCount + correctPos(needPos, 'Open/reverse position by signal');
    end

    -- проверить и при необходимости скорректировать тейк-профит
    if (transCount == 0) then
        transCount = transCount + profitControl();
    end

    -- записать текущие данные в таблицу робота
    putDataToTable(signal);

    -- запомнить текущую позицию
    prevPos = nowPos;

    -- если были транзакции, следующий вызов цикла через 3с, иначе через 0,5c
    if (transCount ~= 0) then
        sleep(3000);
    else
        sleep(500);
    end
end

----------------------------------------------------------------------------------
------------------ Вычисление параметров/коррекция тейк-профита ------------------
----------------------------------------------------------------------------------
function profitControl()
    -- получить массив индексов строк в таблице стоп-заявок для заданного счёта и инструмента
    local function fn1(param1, param2) 
        return param1 == account and param2 == emit;
    end
    local rows = SearchItems('stop_orders', 0, getNumberOf('stop_orders') - 1, fn1, 'account, sec_code');  

    -- шаг цены, берётся из таблицы текущих торгов 
    local step = tonumber(getParamEx(class, emit, 'SEC_PRICE_STEP').param_value);

    -- средняя цена лота последней сделки
    local entryPrice = roundForStep(getEntryPrice(), step);

    -- цена тейк-профита и стоп-лимита
    local profitPrice = entryPrice + sign(nowPos) * profit * step;
    local stopPrice = entryPrice - sign(nowPos) * stop * step;

    -- по умолчанию тейк-профит не существует/не откорретирован
    local profitCorrect = false;

    --счётчик транзакций
    local count = 0;

    -- если в таблице стоп-заявок обнаружены строки для заданного счёта и инструмента
    if (rows ~= nil) then
        -- цикл по массиву индексов обнаруженных строк
        for i = 1, #rows do
            -- получить строку таблицы
            local row = getItem('stop_orders', rows[i]);

            -- если стоп-заявка активна
            local flag = bit.band(row.flags, 0x1);
            if (flag ~= 0) then
                -- если тип стоп-заявки не "тейк-профит и стоп-лимит" или тейк-профит уже откорректирован
                if (row.stop_order_type ~= 9 or profitCorrect) then
                    -- удалить данную запись из таблицы стоп-заявок, это мусор от каких-то сбоев или левых команд пользователя
                    deleteProfit(row.order_num);
                    count = count + 1;
                -- если это неоткорректированный тейк-профит
                else
                    -- количество лотов
                    local quantityX = row.qty;
                    -- стоп-цена
                    local profitPriceX = row.condition_price;

                    local signPosX = 0;
                    -- срабатывание тейк-профита при понижении цены (покупка)
                    if (row.condition == 4) then
                        signPosX = -1;
                    -- срабатывание тейк-профита при повышении цены (продажа)
                    elseif (row.condition == 5) then
                        signPosX = 1;
                    end

                    -- если направление тейк-профита соответствует знаку позиции,
                    -- количество лотов заявки равно количеству лотов позиции
                    -- и стоп-цена заявки равна расчётной,
                    -- то заявка корректна
                    if (signPosX == sign(nowPos) and quantityX == math.abs(nowPos) and profitPriceX == profitPrice) then
                        profitCorrect = true;
                    -- иначе удалить заявку
                    else
                        deleteProfit(row.order_num);
                        count = count + 1;    
                    end
                end
            end
        end
    end

    -- если тейк-профит не существует/не откорректирован и текущая позиция не нулевая 
    if (not profitCorrect and nowPos ~= 0) then
        -- выждать на случай, если стоп-заявка уже сработала и деактивировалась, а сделка ещё не прошла
        sleep(5000);
        -- повторно проверить позицию
        nowPos = getNowPos();
        if (nowPos == 0) then
            return count;
        end

        -- задать отступ от максимума/минимума цены для срабатывания тейк-профита 
        local profitOffset = offset * step;
        -- задать защитный спред при выставлении лимитной заявки
        local profitSpread = spread * step;
        -- задать цену заявки при срабатывании стоп-лимита
        local stopOrderPrice = stopPrice - sign(nowPos) * spread * step;

        local buySell = '';
        -- продажа при срабатывании
        if (nowPos > 0) then
            buySell = 'S'; 
        -- покупка при срабатывании
        else
            buySell = 'B';
        end

        -- выставить новый тейк-профит с заданными параметрами
        newStopProfit(buySell, math.abs(nowPos), profitPrice, profitOffset, profitSpread, stopPrice, stopOrderPrice, 'Create stop order');
        count = count + 1;
    end

    return count;
end

----------------------------------------------------------------------------------
------------- Определение реальной цены, по которой произошла сделка -------------
----------------------------------------------------------------------------------
function getEntryPrice()
    -- если позиция нулевая, тейк-профит ставить не надо - соответственно, цену вычислять не требуется
    if (nowPos == 0) then
        return 0;
    end

    -- получить массив индексов строк в таблице сделок для заданного счёта и инструмента
    local function fn1(param1, param2) 
        return param1 == account and param2 == emit;
    end
    local rows = SearchItems('trades', 0, getNumberOf('trades') - 1, fn1, 'account, sec_code');  

    local pos = nowPos;
    local sum = 0;

    -- если в таблице сделок обнаружены строки с заданными параметрами 
    if (rows ~= nil) then
        -- цикл по массиву индексов обнаруженных строк, начиная с последней сделки
        for i = #rows, 1, -1 do
            -- получить строку таблицы
            local row = getItem('trades', rows[i]);

            -- определить направление сделки
            local direct;
            if (bit.band(row.flags, 0x4) ~= 0) then
                direct = -1;    -- продажа
            else
                direct = 1;     -- покупка
            end

            -- определить позицию, бывшую до текущей записи из перечисляемых в цикле
            local price = row.price;
            local quantity = row.qty;
            local prev = pos - direct * quantity;

            -- если знак позиции изменился, перебраны все записи последней сделки
            if (sign(prev) ~= sign(pos)) then
                -- добавить цену текущей записи к общей сумме сделки
                -- с учётом того, что при реверсе позиции часть лотов может относиться 
                -- к гашению предыдущего отклонения от нулевой позиции
                sum = sum + direct * sign(nowPos) * price * math.min(quantity, math.abs(pos));
                -- вернуть среднюю цену лота сделки
                return sum / math.abs(nowPos);
            -- если знак позиции не изменился, сделка состоит из нескольких частей 
            -- (возможно при позиции более одного лота),
            -- и сумма текущей записи точно добавляется к общей сумме сделки
            else
                sum = sum + direct * sign(nowPos) * price * quantity;
            end

            -- сделать предыдущую позицию текущей
            pos = prev;
        end
    end 

    return 0;
end

----------------------------------------------------------------------------------
--------------- Удаление всех активных стоп-заявок (тейк-профитов) ---------------
----------------------------------------------------------------------------------
function deleteAllProfits(logComment)
    local n = getNumberOf('stop_orders');
    local count = 0;

    for i = 0, n - 1 do
        local row = getItem('stop_orders', i);
        if (row.account == account and row.sec_code == emit and row.class_code == class) then
            if (bit.band(row.flags, 0x1) ~= 0) then -- заявка активна
                deleteProfit(row.order_num, logComment);
                count = count + 1;
            end
        end
    end

    return count;
end

----------------------------------------------------------------------------------
----------------------------- Удаление тейк-профита ------------------------------
----------------------------------------------------------------------------------
function deleteProfit(orderNumber, logComment)
    -- задать параметры транзакции
    transaction = {
        ['ACTION'] = 'KILL_STOP_ORDER',             -- снятие стоп-заявки
        ['SECCODE'] = emit,                         -- код инструмента
        ['CLASSCODE'] = class,                      -- код класса рынка (срочный)
        ['TRANS_ID'] = '123456',                    -- id заявки
        ['STOP_ORDER_KEY'] = intToStr(orderNumber), -- номер снимаемой стоп-заявки
        ['CLIENT_CODE'] = 'ROBOT'                   -- комментарий, отображаемый в таблице стоп-заявок
    };

    -- отправить транзакцию
    local result = sendTransaction(transaction);

    -- записать ответ в журнал
    local sDataString = 'Transaction response = ' .. result;
    for key, val in pairs(transaction) do
        sDataString = sDataString .. key .. ' = ' .. val .. '; ';
    end
    if (logComment ~= nil) then
        sDataString = logComment .. ' ' .. sDataString;
    end
    writeToLogFile(sDataString);
end

----------------------------------------------------------------------------------
---------------------------- Выставление тейк-профита ----------------------------
----------------------------------------------------------------------------------
function newStopProfit(buySell, quantity, profitPrice, profitOffset, profitSpread, stopPrice, stopOrderPrice, logComment)
    -- задать параметры транзакции
    transaction = {
        ['ACTION'] = 'NEW_STOP_ORDER',                  -- новая стоп-заявка
        ['STOP_ORDER_KIND'] = 'TAKE_PROFIT_AND_STOP_LIMIT_ORDER',   -- тип заявки - тейк-профит и стоп-лимит
        ['SECCODE'] = emit,                             -- код инструмента
        ['ACCOUNT'] = account,                          -- счёт клиента
        ['CLASSCODE'] = class,                          -- код класса рынка (срочный)
        ['OPERATION'] = buySell,                        -- направление операции (покупка/продажа)
        ['QUANTITY'] = intToStr(math.abs(quantity)),    -- количество лотов
        ['STOPPRICE'] = intToStr(profitPrice),          -- стоп-цена 1 (тейк-профит) за лот
        ['OFFSET_UNITS'] = 'PRICE_UNITS',               -- шаг отступа равен шагу цены
        ['SPREAD_UNITS'] = 'PRICE_UNITS',               -- шаг защитного спреда равен шагу цены
        ['OFFSET'] = intToStr(profitOffset),            -- величина отступа от максимума/минимума для срабатывания тейк-профита
        ['SPREAD'] = intToStr(profitSpread),            -- величина защитного спреда заявки, выставляемой при срабатывании тейк-профита
        ['STOPPRICE2'] = intToStr(stopPrice),           -- стоп-цена 2 (стоп-лимит)
        ['PRICE'] = intToStr(stopOrderPrice),           -- цена лимитной заявки при срабатывании стоп-лимита    
        ['EXPIRY_DATE'] = 'TODAY',                      -- до окончания торговой сессии (до отмены могут быть проблемы)
        ['TRANS_ID'] = '123456',                        -- id заявки
        ['CLIENT_CODE'] = 'ROBOT'                       -- комментарий, отображаемый в таблице стоп-заявок
    };

    -- отправить транзакцию
    local result = sendTransaction(transaction);

    -- записать ответ в журнал
    local sDataString = 'Transaction response = ' .. result;
    for key, val in pairs(transaction) do
        sDataString = sDataString .. key .. ' = ' .. val .. '; ';
    end
    if (logComment ~= nil) then
        sDataString = logComment .. ' ' .. sDataString;
    end
    writeToLogFile(sDataString);

    return 1;
end

----------------------------------------------------------------------------------
--------------------- Корректировка позиции (подача заявки) ----------------------
----------------------------------------------------------------------------------
function correctPos(needPos, logComment) 
    -- вычислить разность между требуемой и текущей позицией (объём заявки) 
    local vol = needPos - nowPos;
    if (vol == 0) then
        return 0;
    end

    -- флаг "покупка/продажа"
    local buySell = ''; 
    -- цена заявки
    local price = 0;
    -- цена последней сделки в таблице текущих торгов
    local last = tonumber(getParamEx(class, emit, 'LAST').param_value);
    -- шаг цены, также берётся из таблицы текущих торгов 
    local step = tonumber(getParamEx(class, emit, 'SEC_PRICE_STEP').param_value);

    -- на срочном рынке рыночная цена программно не выставляется, требуется лимитная заявка
    if (vol > 0) then 
        buySell = 'B';  -- покупка
        price = last + spread * step; -- по цене выше последней сделки на значение защитного спреда
    else
        buySell = 'S';  -- продажа
        price = last - spread * step; -- по цене ниже последней сделки на значение защитного спреда
    end

    -- задать параметры транзакции
    transaction = {
        ['ACTION'] = 'NEW_ORDER',               -- новая заявка
        ['SECCODE'] = emit,                     -- код инструмента         
        ['ACCOUNT'] = account,                  -- счёт клиента
        ['CLASSCODE'] = class,                  -- код класса рынка (срочный)
        ['OPERATION'] = buySell,                -- направление операции (покупка/продажа)
        ['PRICE'] = intToStr(price),            -- цена за лот
        ['QUANTITY'] = intToStr(math.abs(vol)), -- количество лотов
        ['TYPE'] = 'L',                         -- лимитная заявка
        ['TRANS_ID'] = '123456',                -- id заявки
        ['CLIENT_CODE'] = 'ROBOT'               -- комментарий, отображаемый в таблице заявок
    };

    -- отправить транзакцию
    local result = sendTransaction(transaction);

    -- записать ответ в журнал
    local sDataString = 'Transaction response = ' .. result .. '; Pos = ' .. tostring(nowPos) .. '; ';
    for key, val in pairs(transaction) do
        sDataString = sDataString .. key .. ' = ' .. val .. '; ';
    end
    if (logComment ~= nil) then
        sDataString = logComment .. ' ' .. sDataString;
    end
    writeToLogFile(sDataString);

    -- каждые 0.1 cек проверять текущую позицию
    local count = 1;
    for i = 1, 300 do
        sleep(100);
        local newPos = getNowPos();
        -- если текущая позиция стала равна требуемой, сделать запись в журнале об успешном выполнении сделки
        if (newPos == needPos) then
            err = 'Trade completed in ' .. tostring(count * 100) .. 'ms';
            writeToLogFile(err);
            return 1;
        end
        count = count + 1;
    end

    -- если в течение 30 сек сделка не была выполнена, сделать запись об ошибке
    err = 'Transaction error';
    writeToLogFile(err);
    return nil;
end

----------------------------------------------------------------------------------
-------------------------- Проверка сигнала к торговле ---------------------------
----------------------------------------------------------------------------------
function signalCheck()
    -- получить количество свечей на графиках индикатора Parabolic SAR и курса фьючерса
    local numOfCandlesSAR = getNumCandles(sarId);
    local numOfCandlesPrice = getNumCandles(priceId);
    if (numOfCandlesSAR == nil or numOfCandlesPrice == nil) then
        err = 'No output from chart';
        return 0;
    end

    -- получить последние две свечи для каждого из графиков
    local tSAR, nSAR, _ = getCandlesByIndex(sarId, 0, numOfCandlesSAR - 2, 2);
    local tPrice, nPrice, _ = getCandlesByIndex(priceId, 0, numOfCandlesPrice - 2, 2);
    if (nSAR ~= 2 or nPrice ~= 2) then
        err = 'Candle number error';
        return 0;
    end

    local signal = 0;

    -- здесь и далее работаем по уровням закрытия свечи цены, для SAR уровни закрытия и открытия, по идее, одинаковы
    if (tSAR[1].close < tPrice[1].close) then
        signal = 1; -- цена выше SAR, зона роста цены
    elseif (tSAR[1].close > tPrice[1].close) then
        signal = -1; -- цена ниже SAR, зона падения цены
    end

    -- если нет неподтверждённого сигнала
    if (triggerSignal == 0) then  
        -- переход цены выше SAR - неподтверждённый сигнал к открытию длинной позиции
        if (tSAR[0].close > tPrice[0].close and tSAR[1].close < tPrice[1].close) then
            triggerLevel = tSAR[0].close + triggerOffset;
            triggerSignal = 1;
        -- переход цены ниже SAR - неподтверждённый сигнал к открытию короткой позиции
        elseif (tSAR[0].close < tPrice[0].close and tSAR[1].close > tPrice[1].close) then
            triggerLevel = tSAR[0].close - triggerOffset;
            triggerSignal = -1;
        end
    end

    -- если был неподтверждённый сигнал от SAR
    if (triggerSignal ~= 0) then
        -- переход цены выше SAR сбрасывает предыдущий сигнал на открытие короткой позиции
        if (tSAR[0].close > tPrice[0].close and tSAR[1].close < tPrice[1].close and triggerSignal < 0) then
            triggerSignal = 0;
        -- переход цены ниже SAR сбрасывает предыдущий сигнал на открытие длинной позиции
        elseif (tSAR[0].close < tPrice[0].close and tSAR[1].close > tPrice[1].close and triggerSignal > 0) then
            triggerSignal = 0;
        -- подтверждение сигнала на открытие длинной позиции
        elseif (triggerSignal > 0 and tPrice[1].close > triggerLevel) then
            signal = 2;
            triggerSignal = 0;
        -- подтверждение сигнала на открытие короткой позиции
        elseif (triggerSignal < 0 and tPrice[1].close < triggerLevel) then
            signal = -2;
            triggerSignal = 0;
        end
    end

    return  signal;
end

----------------------------------------------------------------------------------
-------------------- Получение текущей позиции по инструменту --------------------
----------------------------------------------------------------------------------
function getNowPos()
    -- количество записей в таблице "Позиции по клиентским счетам (фьючерсы)"
    local nSize = getNumberOf('futures_client_holding');
    if (nSize == nil) then
        return 0;
    end

    -- просмотр таблицы
    for i = 0, nSize - 1 do
        local row = getItem('futures_client_holding', i);
        -- если в строке совпадает инструмент и торговый счёт, вернуть текущую чистую позицию (кол-во фьючерсов на счёте)
        if (row ~= nil and row.sec_code == emit and row.trdaccid == account) then
            return tonumber(row.totalnet);
        end
    end

    -- иначе вернуть 0
    return 0;
end

----------------------------------------------------------------------------------
-------------------------- Инициализация строк таблицы ---------------------------
----------------------------------------------------------------------------------
function putDataToTableInit()
    Clear(tableId);
    SetWindowPos(tableId, 100, 200, 500, 300);
    SetWindowCaption(tableId, 'Robot Parabolic');
    
    for i = 1, 13 do
        InsertRow(tableId, -1);
    end

    SetCell(tableId, 1, 1, 'Server time');
    SetCell(tableId, 2, 1, 'Emitent code');
    SetCell(tableId, 3, 1, 'Current position');
    SetCell(tableId, 4, 1, 'Signal');
    SetCell(tableId, 5, 1, 'Lot size');
    SetCell(tableId, 9, 1, 'Client code');
    SetCell(tableId, 10, 1, 'Class code');
    SetCell(tableId, 11, 1, 'Trigger level');
    SetCell(tableId, 12, 1, 'Trigger state');
    SetCell(tableId, 13, 1, 'Test');
    SetColor(tableId, 13, 1, RGB(220, 220, 0), RGB(0, 0, 0), RGB(0, 220, 220), RGB(0, 0, 0));
    SetCell(tableId, 13, 3, 'Stop');
    SetColor(tableId, 13, 3, RGB(220, 220, 0), RGB(0, 0, 0), RGB(0, 220, 220), RGB(0, 0, 0));

    local nRow, nCol = GetTableSize(tableId);
    for i = 1, nRow do
        if (i % 2 == 0) then
            SetColor(tableId, i, QTABLE_NO_INDEX, RGB(220, 220, 220), RGB(0, 0, 0), RGB(0, 220, 220), RGB(0, 0, 0));
        else
            SetColor(tableId, i, QTABLE_NO_INDEX, RGB(255, 255, 255), RGB(0, 0, 0), RGB(0, 220, 220), RGB(0, 0, 0));
        end
    end
end

----------------------------------------------------------------------------------
---------------------- Вывод в таблицу сообщения об ошибке -----------------------
----------------------------------------------------------------------------------
function putDataToTableTimer()
    SetCell(tableId, 1, 3, err);
    Highlight(tableId, 1, QTABLE_NO_INDEX, RGB(0, 20, 255), RGB(255, 255, 255), 500);
end

----------------------------------------------------------------------------------
----------------------- Вывод в таблицу текущей информации -----------------------
----------------------------------------------------------------------------------
function putDataToTable(signal, price)
    SetCell(tableId, 2, 2, tostring(emit));
    SetCell(tableId, 3, 2, tostring(nowPos));
    SetCell(tableId, 4, 2, tostring(signal));
    SetCell(tableId, 5, 2, tostring(lot));
    SetCell(tableId, 9, 2, account);
    SetCell(tableId, 10, 2, class);
    SetCell(tableId, 11, 2, tostring(triggerLevel));
    SetCell(tableId, 12, 2, tostring(triggerSignal));
end

----------------------------------------------------------------------------------
---------------------- Запись строки в конец файла журнала -----------------------
----------------------------------------------------------------------------------
function writeToLogFile(sDataString)
    local serverTime = getInfoParam('SERVERTIME');
    local serverData = getInfoParam('TRADEDATE');
    sDataString = serverData .. ' ' .. serverTime .. ' - ' .. sDataString .. '\n';

    local f = io.open(logFileName, 'r+');
    if (f == nil) then
        f = io.open(logName, 'w');
    end
    
    if (f ~= nil) then
        f:seek('end', 0);
        f:write(sDataString);
        f:flush();
        f:close();
    end
end

----------------------------------------------------------------------------------
----------------------------------- Знак числа -----------------------------------
----------------------------------------------------------------------------------
function sign(num)
    if (num > 0) then
        return 1;
    end
    if (num < 0) then
        return -1;
    end
    return 0;
end

----------------------------------------------------------------------------------
----------------- Округление числа до nStep десятичных разрядов ------------------
----------------------------------------------------------------------------------
function roundForStep(num, nStep)
    if (num == nil or nStep == nil) then
        return nil;
    end

    if (nStep == 0) then
        return num;
    end

    local mod = num % nStep;
    if (mod < nStep / 2) then
        return math.floor(num / nStep) * nStep;
    else
        return math.ceil(num / nStep) * nStep;
    end
end

----------------------------------------------------------------------------------
--------------- Преобразование целого числа в строку без 0 десятых ---------------
----------------------- (баг стандартной функции tostring) -----------------------
----------------------------------------------------------------------------------
function intToStr(num) 
    return string.format('%d', num); 
end
