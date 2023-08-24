----------------------------------------------------------------------------------
-------------------------- Тело основного цикла скрипта --------------------------
----------------------------------------------------------------------------------
function body() 
    if (timer > 0) then
        timer = timer - 1;
        putDataToTableTimer();
        sleep(1000);
        return;
    end

    local serverTime = getInfoParam('SERVERTIME');
    if (serverTime == nil or serverTime == '') then
        err = 'undefined (no connect)';
        timer = 3;
        return;
    else
        err = '';
    end

    if (IsWindowClosed(tableId)) then
        CreateWindow(tableId);    
        putDataToTableInit();    
    end

    local sessionStatus = tonumber(getParamEx(class, emit, 'STATUS').param_value);
    if (sessionStatus ~= 1) then 
        err = 'Session closed';
        timer = 3;
        return;
    end    

    local onTableEvent = function(tableId, msg, row, col)
        if (msg == QTABLE_LBUTTONDBLCLK) then
            if (row == 13 and col == 1) then
                message('Test message');
            end
            if (row == 13 and col == 3) then
                isRun = false;
            end
        end
    end

    SetTableNotificationCallback(tableId, onTableEvent);

    SetCell(tableId, 1, 2, serverTime);
    SetCell(tableId, 1, 3, err);

    err = '';

    -- найти текущую позицию по инструменту
    nowPos = getNowPos();

    -- если переворот или закрытие позиции, убрать профит
    if (nowPos == 0 or sign(nowPos) ~= sign(prevPos)) then
        deleteAllProfits('Remove take profit');
    end

    -- проверить наличие сигнала с графика
    local signal = signalCheck();

    -- скорректировать сигнал с учётом "только лонг" или "только шорт"

    -- если сигнал лонг или шорт, то купить или продать

    -- проверить, что мы не против показания индикатора

    -- найти цену входа

    -- проверить правильность профита

    -- записать текущие данные в таблицу робота
    putDataToTable(nowPos);

    -- запомнить текущую позицию
    prevPos = nowPos;

    sleep(1000);
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
        sDataString = logComment .. sDataString;
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
        sDataString = logComment .. sDataString;
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
        sDataString = logComment .. sDataString;
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
function putDataToTable(pos)
    SetCell(tableId, 3, 2, tostring(pos));
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
    SetCell(tableId, 2, 1, 'Код бумаги');
    SetCell(tableId, 3, 1, 'Current position');
    SetCell(tableId, 4, 1, 'Сигнал ТС');
    SetCell(tableId, 5, 1, 'Лот');
    SetCell(tableId, 7, 1, 'Номер счёта'); SetCell(tableId, 7, 3, 'Номер счёта на ФОРТС');
    SetCell(tableId, 8, 1, 'Код класса');
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
----------------------------------
----------------------------------------------------------------------------------
function putDataToTableTimer()
    SetCell(tableId, 1, 3, err);
    Highlight(tableId, 1, QTABLE_NO_INDEX, RGB(0, 20, 255), RGB(255, 255, 255), 500);
end


----------------------------------------------------------------------------------
----------------------------------
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
