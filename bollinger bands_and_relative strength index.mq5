/* based on original code from rafaelfvcs/Introduction to MetaTrader5 and MQL5 book.
Available at: <https://github.com/rafaelfvcs/Introduction-to-MetaTrader5-and-MQL5---book/blob/master/MM_CROS_IFR.mq5>
Reproduced under the original author's permission */

// gives the user trading options 
enum trade_strategy
  {
   bb_only,  // Bollinger Bands only strategy
   rsi_only, // Relative Strength Index only strategy
   bb_and_rsi    // Combined Bollinger Bands and Relative Strength Index strategy
  };

// shows at, the start screen, which strategy is to be used
sinput string s0; //Trade entry strategy
input trade_strategy strategy = bb_and_rsi; // trading strategy

//bollinger bands parameters
sinput string s1;
input int bb_middle_period = 20; // bollinger bands default period
input double bb_deviation = 2.0; // deviation fom the middle line
input int bb_shift = 0; // bollinger bands horizontal shift
input ENUM_TIMEFRAMES bb_period = PERIOD_CURRENT; // strategy timeframe to be used
input ENUM_APPLIED_PRICE bb_price = PRICE_CLOSE; // price where the bb will be applied to

//relative strength index parameters
sinput string s2;
input int rsi_ma_period = 14; // rsi moving average period
input int rsi_over_bought = 70; // rsi upper limit
input int rsi_over_sell = 30;// rsi lower limit
input ENUM_APPLIED_PRICE rsi_price = PRICE_CLOSE; // price where the rsi will be applied to
input ENUM_TIMEFRAMES rsi_period = PERIOD_CURRENT;// rsi period

//additional parameters
sinput string s3;
input int qty = 100; // equity quantity to be traded
input double TP = 60; // take profit level
input double SL = 30; // stop loss level
input string time_limit = "17:40"; // time limit to close open positions

//--- rsi - relative strength index global variables
int rsi_handle; // relative strength index handle
double rsi_buffer[]; // relative strength index buffer

//--- bb - bollinger bands global variables
int bb_handle; // bollinger bands handle
double bb_middle_buffer[]; // bollinger bands middle buffer - 0 index
double bb_upper_buffer[]; // bollinger bands upper buffer - 1 index
double bb_lower_buffer[]; // bollinger bands lower buffer - 2 index

// some other useful global variables
MqlRates candles[]; // candles holder
MqlTick tick; // ticks holder
static double last_price; // gets the last deal price

// optional, user-generated argument to uniquely identify an expert advisor robot
int robot_id = 20180219;

//+------------------------------------------------------------------+
//| Expert Advisor initialization function                           |
//+------------------------------------------------------------------+
int OnInit()
  {
   /* initiates and get the user-defined parameters for the bollinger bands and
      the relative strength index indicators */
   bb_handle = iBands(_Symbol,bb_period,bb_middle_period,bb_shift,bb_deviation,bb_price);
   rsi_handle = iRSI(_Symbol,rsi_period,rsi_ma_period,rsi_price);
   
   /* gets from the data service provider the last 4 equity rates,
      then sort them descendently */
   CopyRates(_Symbol,_Period,0,4,candles);
   ArraySetAsSeries(candles,true);
   
   // puts the bollinger bands lines on the 0-th window, 0-th sub-window
   ChartIndicatorAdd(0,0,bb_handle);
   // puts the relative strength line on the 0-th window, 1-th sub-window
   ChartIndicatorAdd(0,1,rsi_handle);
   
   // closes the OnInit function
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert Advisor deinitialization function                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   // frees the chart from the previously added indicators lines
   IndicatorRelease(bb_handle);
   IndicatorRelease(rsi_handle);
  }

//+------------------------------------------------------------------+
//| Expert Advisor OnTick function                                   |
//+------------------------------------------------------------------+
void OnTick()
  {
   /* gets, from the previously initiated bb and rsi handlers, the (0,1,2)
      indexed buffers, 0-shifted, 4 lengthed buffers. then, set them as
      array series and sort them descendently. the buffer numbers are as
      the following:       0 - BASE_LINE, 1 - UPPER_BAND, 2 - LOWER_BAND */
   CopyBuffer(bb_handle,0,0,4,bb_middle_buffer);
   CopyBuffer(bb_handle,1,0,4,bb_upper_buffer);
   CopyBuffer(bb_handle,2,0,4,bb_lower_buffer);
   CopyBuffer(rsi_handle,0,0,4,rsi_buffer);
   ArraySetAsSeries(rsi_buffer,true);
   ArraySetAsSeries(bb_middle_buffer,true);
   ArraySetAsSeries(bb_upper_buffer,true);
   ArraySetAsSeries(bb_lower_buffer,true);

   /* gets the 1-buffered, 4-lengthed candles handler
      set it as an array series, them sort it descendently */
   CopyRates(_Symbol,_Period,0,4,candles);
   ArraySetAsSeries(candles,true);

   // feeds the variable with the stock last price
   SymbolInfoTick(_Symbol,tick);
   last_price = tick.last;


   bool buy_bb = bb_lower_buffer[2] < last_price &&
                  bb_lower_buffer[0] > last_price;
   bool buy_rsi = rsi_buffer [0] <= rsi_over_sell;

   // sets the logical conditions for the sell orders   
   bool sell_bb = bb_upper_buffer[2] > last_price &&
                  bb_upper_buffer[0] < last_price;
   bool sell_rsi = rsi_buffer[0] >= rsi_over_bought;
   
   // when turned to ture, selects the buy/sell strategies
   bool how_to_buy = false;
   bool how_to_sell  = false;

   // sets the user-defined trading strategy
   if(strategy == bb_only)
     {
      how_to_buy = buy_bb;
      how_to_sell  = sell_bb;
     }
   else
      if(strategy == rsi_only)
        {
         how_to_buy = buy_rsi;
         how_to_sell  = sell_rsi;
        }
      else
        {
         how_to_buy = buy_bb && buy_rsi;
         how_to_sell  = sell_bb && sell_rsi;
        }

   // returns true if we got a new candle under the chart timeframe
   bool gotta_new_candle = gotta_new_candle();

   /* draws blue/red colored vertical lines on the chart, each time 
      the algorithm opens a buy/sell position */
   if(gotta_new_candle)
     {
      if(how_to_buy && PositionSelect(_Symbol)==false)
        {
         vertical_line_draw("Compra",candles[1].time,clrBlue);
         market_buy();
        }
      if(how_to_sell && PositionSelect(_Symbol)==false)
        {
         vertical_line_draw("Venda",candles[1].time,clrRed);
         market_sell();
        }
     }

   // check whether or not is time to close the daily positions
   if(TimeToString(TimeCurrent(),TIME_MINUTES) == time_limit && PositionSelect(_Symbol)==true)
     {
      Print("We are close to the market end time: starting to close open positions.");
      if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
        {
         buy_closing();
        }
      else
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
           {
            sell_closing();
           }
     }

  }

// function to place the blue/red vertical lines on the chart, indicating buy/sell positions
void vertical_line_draw(string name, datetime dt, color color_ = clrAliceBlue)
  {
   ObjectDelete(0,name);
   ObjectCreate(0,name,OBJ_VLINE,0,dt,0);
   ObjectSetInteger(0,name,OBJPROP_COLOR,color_);
  }

// places a buy order based on market current price
void market_buy()
  {
   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action = TRADE_ACTION_DEAL; // code to place an order at the market price
   request.magic = robot_id; // user-defined robot id
   request.symbol = _Symbol; // stock symbol
   request.volume = qty; // quantity to be negotiated
   request.price = NormalizeDouble(tick.ask,_Digits); // gets the buy price from the best SELLER (lowest price)
   request.sl = NormalizeDouble(tick.ask - SL*_Point,_Digits); // stop loss level
   request.tp = NormalizeDouble(tick.ask + TP*_Point,_Digits); // take profit level
   request.deviation = 0; // buying price permitted deviation
   request.type = ORDER_TYPE_BUY; // code to place the BUY market order
   request.type_filling = ORDER_FILLING_FOK; /* Fill Or Kill: if it cannot be placed fulfilling the whole specified
                                                volume and price, the order will be dropped */

   // sends the order request, getting a result code
   OrderSend(request,result);

   // write on the log the placed order results
   if(result.retcode == 10008 || result.retcode == 10009)
     {
      Print("The buy order was successfully fulfilled.");
     }
   else
     {
      Print("The buy order was not fulfilled. Error code: ", GetLastError());
      ResetLastError();
     }
  }

// places a sell order based on market current price
void market_sell()
  {
   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action = TRADE_ACTION_DEAL; // code to place an order at the market price
   request.magic = robot_id; // user-defined robot id
   request.symbol = _Symbol; // stock symbol
   request.volume= qty; // quantity to be negotiated
   request.price = NormalizeDouble(tick.bid,_Digits); // gets the sell price from the best BUYER (highest price)
   request.sl = NormalizeDouble(tick.bid + SL*_Point,_Digits); // stop loss level
   request.tp = NormalizeDouble(tick.bid - TP*_Point,_Digits);// take profit level
   request.deviation = 0; // selling price permitted deviation
   request.type = ORDER_TYPE_SELL; // code to place the SELL market order
   request.type_filling = ORDER_FILLING_FOK; /* Fill Or Kill: if it cannot be placed fulfilling the whole specified
                                                volume and price, the order will be dropped */
   
   // sends the order request, getting a result code
   OrderSend(request,result);
   
   // write on the log the placed order results
   if(result.retcode == 10008 || result.retcode == 10009)
     {
      Print("The sell order was successfully fulfilled.");
     }
   else
     {
      Print("The sell order was not fulfilled. Error code: ", GetLastError());
      ResetLastError();
     }
  }

// places at the end of the day a closing sell order based on the market current price
void sell_closing()
  {
   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action = TRADE_ACTION_DEAL; // code to place an order at the market price
   request.magic = robot_id; // user-defined robot id
   request.symbol = _Symbol; // stock symbol
   request.volume = qty; // quantity to be negotiated
   request.price = 0; // accepts the market bid price
   request.type = ORDER_TYPE_SELL; // code to place the SELL market order
   request.type_filling = ORDER_FILLING_RETURN; /* as there is time to negotiate (20 minutes prior to 
                                                market closing time), tries to fulfill the sell order 
                                                until the quantity is fully fulfilled */

   // sends the order request, getting a result code
   OrderSend(request,result);

   // write on the log the placed order results
   if(result.retcode == 10008 || result.retcode == 10009)
     {
      Print("The sell order was successfully fulfilled.");
     }
   else
     {
      Print("The sell order was not fulfilled. Error code: ", GetLastError());
      ResetLastError();
     }
  }

// places at the end of the day a closing buy order based on the market current price
void buy_closing()
  {
   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action = TRADE_ACTION_DEAL; // code to place an order at the market price
   request.magic = robot_id; // user-defined robot id
   request.symbol = _Symbol; // stock symbol
   request.volume = qty; // quantity to be negotiated
   request.price = 0; // accepts the market bid price
   request.type = ORDER_TYPE_BUY; // code to place the BUY market order
   request.type_filling = ORDER_FILLING_RETURN; /* as there is time to negotiate (20 minutes prior to 
                                                market closing time), tries to fulfill the buy order 
                                                until the quantity is fully fulfilled */
   
   // sends the order request, getting a result code
   OrderSend(request,result);

   // write on the log the placed order results
   if(result.retcode == 10008 || result.retcode == 10009)
     {
      Print("The buy order was successfully fulfilled.");
     }
   else
     {
      Print("The sell order was not fulfilled. Error code: ", GetLastError());
      ResetLastError();
     }
  }
  
// identifies whether or not the market got a new candle at the chart timeframe
bool gotta_new_candle()
  {
   // gets the opening time of the last candle
   static datetime last_time=0;
   // gets the current time
   datetime lastbar_time= (datetime) SeriesInfoInteger(Symbol(),Period(),SERIES_LASTBAR_DATE);

   // for the first function call, run this
   if(last_time==0)
     {
      // saves the current time and exits the function
      last_time=lastbar_time;
      return(false);
     }

   // for all the other function runs
   if(last_time!=lastbar_time)
     {
      // saves the current time and exits the function
      last_time=lastbar_time;
      return(true);
     }
   // if the code reach this line, there is not a new candle, then exits the function
   return(false);
  }
