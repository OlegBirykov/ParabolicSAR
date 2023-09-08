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

    -- если переворот или закрытие позиции, убрать прежние профиты
    if (nowPos == 0 or sign(nowPos) ~= sign(prevPos)) then
        -- здесь и далее такая конструкция автоматически положит програаму, если функция вернёт nil
        transCount = transCount + deleteAllProfits('Remove take profit');
    end

    -- проверить наличие сигнала с графика
    local signal = signalCheck();

    -- скорректировать сигнал с учётом "Только лонг" или "Только шорт"
    if (tradeType == 'LONG') then
        signal = math.max(signal, 0);
    elseif (tradeType == 'SHORT') then 
        signal = math.min(signal, 0);
    end

    -- если сигнал лонг или шорт, то купить или продать
    if (math.abs(signal) == 2) then
        local needPos = sign(signal) * lot;
        transCount = transCount + correctPos(needPos, 'Open/reverse position by signal');
    -- принудительное закрытие позиции, противоречащей текущему состоянию индикатора
    elseif (math.abs(signal) == 1 and sign(signal) ~= sign(nowPos)) then
        transCount = transCount + correctPos(0, 'Incorrect sign of current position, close position');
    -- принудительное закрытие шорта в режиме "Только лонг"
    elseif (tradeType == 'LONG' and nowPos < 0) then
        transCount = transCount + correctPos(0, 'Mode "Only long", close short position');
    -- принудительное закрытие лонга в режиме "Только шорт"
    elseif (tradeType == 'SHORT' and nowPos > 0) then
        transCount = transCount + correctPos(0, 'Mode "Only short", close long position');
    end

    -- проверить правильность профита
    if (transCount == 0) then
        transCount = transCount + profitControl();
    end

    -- записать текущие данные в таблицу робота
    putDataToTable(signal);

    -- запомнить текущую позицию
    prevPos = nowPos;

    if (transCount ~= 0) then
        sleep(3000);
    else
        sleep(500);
    end
end

----------------------------------------------------------------------------------
----------------------------------
----------------------------------------------------------------------------------
function profitControl()
    local function fn1(param1, param2) 
        return param1 == account and param2 == emit;
    end

    local rows = SearchItems('stop_orders', 0, getNumberOf('stop_orders') - 1, fn1, 'account, sec_code');  
    local step = tonumber(getParamEx(class, emit, 'SEC_PRICE_STEP').param_value);
    local entryPrice = roundForStep(getEntryPrice(), step);
    local profitPrice = entryPrice + sign(nowPos) * profit * step;
    local profitCorrect = false;  -- нашли или нет нужный профит
    local count = 0;

    if (rows ~= nil) then
        for i = 1, #rows do
            local row = getItem('stop_orders', i);
            local flag = bit.band(row.flags, 0x1);  -- флаг активной заявки
            if (flag ~= 0) then
                if (row.stop_order_type ~= 6 or profitCorrect) then -- 6 - тейк-профит
                    deleteProfit(row.orderNumber);
                    count = count + 1;
                else
                    local quantityX = row.qty;
                    local profitPriceX = row.condition_price;
                    local signPosX = 0;
                    if (row.condition == 4) then
                        signPosX = -1;
                    elseif (row.condition == 5) then
                        signPosX = 1;
                    end

                    if (signPosX == sign(nowPos) and quantityX == math.abs(nowPos) and profitPriceX == profitPrice) then
                        profitCorrect = true;
                    else
                        deleteProfit(row.orderNumber);
                        count = count + 1;    
                    end
                end
            end
        end
    end

    if (not profitCorrect and nowPos ~= 0) then
        local profitSpread = 30 * step;
        local buySell = '';

        if (nowPos > 0) then
            buySell = 'S';
        else
            buySell = 'B';
        end

        newStopProfit(buySell, math.abs(nowPos), profitPrice, 0, profitSpread, 'Create stop order');
        count = count + 1;
    end

    return count;
end

----------------------------------------------------------------------------------
----------------------------------
----------------------------------------------------------------------------------
function getEntryPrice()
    if (nowPos == 0) then
        return 0;
    end

    local function fn1(param1, param2) 
        return param1 == account and param2 == emit;
    end

    local rows = SearchItems('trades', 0, getNumberOf('trades') - 1, fn1, 'account, sec_code');  
    local pos = nowPos;
    local sum = 0;

    if (rows ~= nil) then
        for i = #rows, 1, -1 do
            local row = getItem('trades', i);
            local direct;

            if (bit.band(row.flags, 0x4) ~= 0) then
                direct = -1;    -- продажа
            else
                direct = 1;     -- покупка
            end

            local price = row.price;
            local quantity = row.qty;
            local prev = pos - direct * quantiy;

            if (sign(prev) ~= sign(pos)) then
                sum = sum + direct * sign(nowPos) * price * math.min(quantity, math.abs(pos));
                return sum / math.abs(nowPos);
            else
                sum = sum + direct * sign(nowPos) * price * quantity;
            end

            pos = prev;
        end
    end 

    return 0;
end

----------------------------------------------------------------------------------
----------------------------------
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
----------------------------------
----------------------------------------------------------------------------------
function deleteProfit(orderNumber, logComment)
    transaction = {
        ['ACTION'] = 'KILL_STOP_ORDER',
        ['SECCODE'] = emit,
        ['CLASSCODE'] = class,
        ['TRANS_ID'] = '123456',
        ['STOP_ORDER_KEY'] = intToStr(orderNumber),
        ['CLIENT_CODE'] = 'ROBOT'
    };

    local result = sendTransaction(transaction);

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
----------------------------------
----------------------------------------------------------------------------------
function newStopProfit(buySell, quantity, stopPrice, offset, spread, logComment)
    transaction = {
        ['ACTION'] = 'NEW_STOP_ORDER',
        ['STOP_ORDER_KIND'] = 'TAKE_PROFIT_STOP_ORDER',
        ['SECCODE'] = emit,
        ['ACCOUNT'] = account,
        ['CLASSCODE'] = class,
        ['OPERATION'] = buySell,
        ['QUANTITY'] = intToStr(math.abs(quantity)),
        ['STOPPRICE'] = intToStr(stopPrice),
        ['OFFSET_UNITS'] = 'PRICE_UNITS',
        ['SPREAD_UNITS'] = 'PRICE_UNITS',
        ['OFFSET'] = intToStr(offset),
        ['SPREAD'] = intToStr(spread),
        ['EXPIRY_DATE'] = 'GTC',  -- до отмены
        ['TRANS_ID'] = '123456',
        ['CLIENT_CODE'] = 'ROBOT'
    };

    local result = sendTransaction(transaction);

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
----------------------------------
----------------------------------------------------------------------------------
function correctPos(needPos, logComment) 
    local vol = needPos - nowPos;
    if (vol == 0) then
        return 0;
    end

    local buySell = '';
    local price = 0;
    local last = tonumber(getParamEx(class, emit, 'LAST').param_value);
    local step = tonumber(getParamEx(class, emit, 'SEC_PRICE_STEP').param_value);

    if (vol > 0) then 
        buySell = 'B';
        price = last + slip * step;
    else
        buySell = 'S';
        price = last - slip * step;
    end

    transaction = {
        ['ACTION'] = 'NEW_ORDER',
        ['SECCODE'] = emit,
        ['ACCOUNT'] = account,
        ['CLASSCODE'] = class,
        ['OPERATION'] = buySell,
        ['PRICE'] = intToStr(price),
        ['QUANTITY'] = intToStr(math.abs(vol)),
        ['TYPE'] = 'L',
        ['TRANS_ID'] = '123456',
        ['CLIENT_CODE'] = 'ROBOT'
    };

    local result = sendTransaction(transaction);

    local sDataString = 'Transaction response = ' .. result .. '; Pos = ' .. tostring(nowPos) .. '; ';
    for key, val in pairs(transaction) do
        sDataString = sDataString .. key .. ' = ' .. val .. '; ';
    end
    if (logComment ~= nil) then
        sDataString = logComment .. ' ' .. sDataString;
    end
    writeToLogFile(sDataString);

    local count = 1;
    for i = 1, 300 do
        sleep(100);
        local newPos = getNowPos();
        if (newPos == needPos) then
            err = 'Trade completed in ' .. tostring(count * 100) .. 'ms';
            writeToLogFile(err);
            return 1;
        end
        count = count + 1;
    end

    err = 'Transaction error';
    writeToLogFile(err);
    return nil;
end

----------------------------------------------------------------------------------
----------------------------------
----------------------------------------------------------------------------------
function signalCheck()
    local numOfCandlesSAR = getNumCandles(sarId);
    local numOfCandlesPrice = getNumCandles(priceId);
    if (numOfCandlesSAR == nil or numOfCandlesPrice == nil) then
        err = 'No output from chart';
        return 0;
    end

    local tSAR, nSAR, _ = getCandlesByIndex(sarId, 0, numOfCandlesSAR - 2, 2);
    local tPrice, nPrice, _ = getCandlesByIndex(priceId, 0, numOfCandlesPrice - 2, 2);
    if (nSAR ~= 2 or nPrice ~= 2) then
        err = 'Candle number error';
        return 0;
    end

    if (tSAR[0].close > tPrice[0].close and tSAR[1].close < tPrice[1].close) then
        return 2; -- сигнал к открытию длинной позиции
    elseif (tSAR[0].close < tPrice[0].close and tSAR[1].close > tPrice[1].close) then
        return -2; -- сигнал к открытию короткой позиции
    elseif (tSAR[1].close < tPrice[1].close) then
        return 1; -- сейчас длинная или нулевая позиция
    elseif (tSAR[1].close > tPrice[1].close) then
        return -1; -- сейчас короткая или нулевая позиция
    end
end

----------------------------------------------------------------------------------
----------------------------------
----------------------------------------------------------------------------------
function getNowPos()
    local nSize = getNumberOf('futures_client_holding');
    if (nSize == nil) then
        return 0;
    end

    for i = 0, nSize - 1 do
        local row = getItem('futures_client_holding', i);
        if (row ~= nil and row.sec_code == emit and row.trdaccid == account) then
            return tonumber(row.totalnet);
        end
    end

    return 0;
end

----------------------------------------------------------------------------------
----------------------------------
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
    SetCell(tableId, 7, 1, 'Client code');
    SetCell(tableId, 8, 1, 'Class code');
    SetCell(tableId, 9, 1, 'Trade type');
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
---------------------
----------------------------------------------------------------------------------
function putDataToTableTimer()
    SetCell(tableId, 1, 3, err);
    Highlight(tableId, 1, QTABLE_NO_INDEX, RGB(0, 20, 255), RGB(255, 255, 255), 500);
end

----------------------------------------------------------------------------------
----------------------------------
----------------------------------------------------------------------------------
function putDataToTable(signal)
    SetCell(tableId, 2, 2, tostring(emit));
    SetCell(tableId, 3, 2, tostring(nowPos));
    SetCell(tableId, 4, 2, tostring(signal));
    SetCell(tableId, 5, 2, tostring(lot));
    SetCell(tableId, 7, 2, account);
    SetCell(tableId, 8, 2, class);
    SetCell(tableId, 9, 2, tradeType);
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
