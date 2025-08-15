//+------------------------------------------------------------------+
//|                     EnhancedLiquidityConfluenceZones.mq4         |
//|                        Copyright 2023, MetaQuotes Software Corp. |
//|                                             https://www.deepseek.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023, Based on Smart Money Concepts"
#property link      "https://www.deepseek.com"
#property version   "4.1"
#property strict
#property indicator_chart_window

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
input int    SwingLookback = 5;          // Swing detection sensitivity (bars)
input int    FibPeriod = 100;            // Fibonacci calculation period
input double RoundLevelStep = 50.0;      // Round number step (in pips)
input double MergeTolerance = 10.0;      // Level merging tolerance (pips)
input int    MinFactors = 2;             // Minimum confluence factors required
input int    TestLookback = 500;         // Number of bars to check for tests
input int    TestTouchPips = 5;          // Pips distance to count as a test
input color  SupportColor = clrGreen;    // Support zone color
input color  ResistanceColor = clrRed;   // Resistance zone color
input int    LineWidth = 2;              // Line width

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
double pipMultiplier;
double touchDistance;
string levelPrefix = "ConfluenceLevel_";

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   pipMultiplier = GetPipMultiplier();
   touchDistance = TestTouchPips * pipMultiplier * Point;
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   DeleteAllConfluenceLines();
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   static datetime lastBarTime = 0;
   static double lastMinPrice = 0;
   static double lastMaxPrice = 0;
   
   double currentMinPrice = ChartGetDouble(0, CHART_PRICE_MIN, 0);
   double currentMaxPrice = ChartGetDouble(0, CHART_PRICE_MAX, 0);
   
   bool newBar = (prev_calculated == 0) || (time[0] != lastBarTime);
   bool viewChanged = (MathAbs(currentMinPrice - lastMinPrice) > 10*Point || 
                      MathAbs(currentMaxPrice - lastMaxPrice) > 10*Point);
   
   if(newBar || viewChanged)
   {
      DeleteAllConfluenceLines();
      
      double tolerance = MergeTolerance * pipMultiplier * Point;
      
      // Collect all confluence factors
      double candPrices[];
      int candSources[];
      
      // 1. Add round number levels
      AddRoundNumberLevels(currentMinPrice, currentMaxPrice, candPrices, candSources);
      
      // 2. Add swing point levels
      AddSwingPointLevels(rates_total, high, low, candPrices, candSources);
      
      // 3. Add Fibonacci levels
      AddFibonacciLevels(rates_total, high, low, candPrices, candSources);
      
      // Merge and draw significant levels
      ProcessConfluenceLevels(candPrices, candSources, tolerance, close[0], 
                             rates_total, high, low, close, time);
      
      lastBarTime = time[0];
      lastMinPrice = currentMinPrice;
      lastMaxPrice = currentMaxPrice;
   }
   else
   {
      UpdateLineColors(close[0]);
   }
   
   return(rates_total);
}

//+------------------------------------------------------------------+
//| Calculate pip multiplier for different brokers                   |
//+------------------------------------------------------------------+
double GetPipMultiplier()
{
   if(Digits == 5 || Digits == 3) return 10.0;
   return 1.0;
}

//+------------------------------------------------------------------+
//| Add round number psychological levels                            |
//+------------------------------------------------------------------+
void AddRoundNumberLevels(double minPrice, double maxPrice, double &candPrices[], int &candSources[])
{
   double step = RoundLevelStep * pipMultiplier * Point;
   double start = MathFloor(minPrice / step) * step;
   double end = MathCeil(maxPrice / step) * step;
   
   for(double price = start; price <= end; price += step)
   {
      int size = ArraySize(candPrices);
      ArrayResize(candPrices, size+1);
      ArrayResize(candSources, size+1);
      candPrices[size] = NormalizeDouble(price, Digits);
      candSources[size] = 1; // Source: Psychological level (bit 0)
   }
}

//+------------------------------------------------------------------+
//| Add swing high/low levels                                        |
//+------------------------------------------------------------------+
void AddSwingPointLevels(int rates_total, const double &high[], const double &low[], 
                         double &candPrices[], int &candSources[])
{
   if(rates_total < SwingLookback*2+1) return;
   
   for(int i = SwingLookback; i < rates_total - SwingLookback; i++)
   {
      if(IsSwingHigh(i, SwingLookback, high, rates_total))
      {
         int size = ArraySize(candPrices);
         ArrayResize(candPrices, size+1);
         ArrayResize(candSources, size+1);
         candPrices[size] = NormalizeDouble(high[i], Digits);
         candSources[size] = 2; // Source: Swing point (bit 1)
      }
      
      if(IsSwingLow(i, SwingLookback, low, rates_total))
      {
         int size = ArraySize(candPrices);
         ArrayResize(candPrices, size+1);
         ArrayResize(candSources, size+1);
         candPrices[size] = NormalizeDouble(low[i], Digits);
         candSources[size] = 2; // Source: Swing point (bit 1)
      }
   }
}

//+------------------------------------------------------------------+
//| Add Fibonacci retracement levels                                 |
//+------------------------------------------------------------------+
void AddFibonacciLevels(int rates_total, const double &high[], const double &low[], 
                        double &candPrices[], int &candSources[])
{
   if(rates_total < FibPeriod) return;
   
   int highIdx = iHighest(Symbol(), 0, MODE_HIGH, FibPeriod, 0);
   int lowIdx  = iLowest(Symbol(), 0, MODE_LOW, FibPeriod, 0);
   if(highIdx < 0 || lowIdx < 0) return;
   
   double swingHigh = high[highIdx];
   double swingLow  = low[lowIdx];
   double range = swingHigh - swingLow;
   if(range <= 0) return;
   
   // Fixed Fibonacci levels initialization
   double fibLevels[5];
   fibLevels[0] = swingHigh - 0.236 * range;
   fibLevels[1] = swingHigh - 0.382 * range;
   fibLevels[2] = swingHigh - 0.500 * range;
   fibLevels[3] = swingHigh - 0.618 * range;
   fibLevels[4] = swingHigh - 0.786 * range;
   
   for(int i = 0; i < 5; i++)
   {
      int size = ArraySize(candPrices);
      ArrayResize(candPrices, size+1);
      ArrayResize(candSources, size+1);
      candPrices[size] = NormalizeDouble(fibLevels[i], Digits);
      candSources[size] = 4; // Source: Fibonacci level (bit 2)
   }
}

//+------------------------------------------------------------------+
//| Helper: build sorted index by price (ascending)                  |
//+------------------------------------------------------------------+
void BuildSortedIndexByPrice(const double &prices[], int &indices[])
{
   int n = ArraySize(prices);
   ArrayResize(indices, n);
   for(int i = 0; i < n; i++) indices[i] = i;
   
   // Selection sort by prices[indices[*]]
   for(int i = 0; i < n - 1; i++)
   {
      int minPos = i;
      for(int j = i + 1; j < n; j++)
      {
         if(prices[indices[j]] < prices[indices[minPos]])
            minPos = j;
      }
      if(minPos != i)
      {
         int tmp = indices[i];
         indices[i] = indices[minPos];
         indices[minPos] = tmp;
      }
   }
}

//+------------------------------------------------------------------+
//| Process and draw confluence levels                               |
//+------------------------------------------------------------------+
void ProcessConfluenceLevels(double &candPrices[], int &candSources[], double tolerance, 
                             double currentPrice, int rates_total, const double &high[], 
                             const double &low[], const double &close[], const datetime &time[])
{
   int total = ArraySize(candPrices);
   if(total == 0) return;
   
   // Sort by price while preserving source mapping using an index array
   int order[];
   BuildSortedIndexByPrice(candPrices, order);
   
   // Merge nearby levels
   double mergedPrices[];
   int mergedSources[];
   int mergedFactors[];
   ArrayResize(mergedFactors, 0);
   
   for(int ii = 0; ii < total; ii++)
   {
      int i = order[ii];
      double price = NormalizeDouble(candPrices[i], Digits);
      int source = candSources[i];
      
      bool merged = false;
      int mergedCount = ArraySize(mergedPrices);
      int bestIndex = -1;
      double bestDistance = 0.0;
      
      for(int j = 0; j < mergedCount; j++)
      {
         double distance = MathAbs(price - mergedPrices[j]);
         if(distance <= tolerance)
         {
            if(!merged || distance < bestDistance)
            {
               merged = true;
               bestIndex = j;
               bestDistance = distance;
            }
         }
      }
      
      if(merged && bestIndex >= 0)
      {
         // Weighted average to keep merged level stable
         double newAverage = ((mergedPrices[bestIndex] * mergedFactors[bestIndex]) + price) / (mergedFactors[bestIndex] + 1);
         mergedPrices[bestIndex] = NormalizeDouble(newAverage, Digits);
         mergedSources[bestIndex] |= source; // Combine bit flags
         mergedFactors[bestIndex]++;
      }
      else
      {
         // Create new level
         int size = ArraySize(mergedPrices);
         ArrayResize(mergedPrices, size+1);
         ArrayResize(mergedSources, size+1);
         ArrayResize(mergedFactors, size+1);
         mergedPrices[size] = price;
         mergedSources[size] = source;
         mergedFactors[size] = 1;
      }
   }
   
   // Draw significant levels
   for(int i = 0; i < ArraySize(mergedPrices); i++)
   {
      int factorCount = 0;
      int src = mergedSources[i];
      while(src > 0) { if((src & 1) != 0) factorCount++; src >>= 1; }
      if(factorCount >= MinFactors)
      {
         int testCount = CountLevelTests(mergedPrices[i], rates_total, high, low, close, time);
         DrawConfluenceLine(mergedPrices[i], mergedSources[i], testCount, currentPrice);
      }
   }
}

//+------------------------------------------------------------------+
//| Count how many times price tested this level without breaking    |
//+------------------------------------------------------------------+
int CountLevelTests(double levelPrice, int rates_total, const double &high[], 
                    const double &low[], const double &close[], const datetime &time[])
{
   int testCount = 0;
   int lookbackBars = MathMin(rates_total, TestLookback);
   bool lastTestWasRejection = false;
   double upperBound = levelPrice + touchDistance;
   double lowerBound = levelPrice - touchDistance;
   
   for(int i = 0; i < lookbackBars; i++)
   {
      bool touched = (high[i] >= lowerBound && low[i] <= upperBound);
      bool upsideRejection = touched && (close[i] < levelPrice);
      bool downsideRejection = touched && (close[i] > levelPrice);
      
      bool rejected = upsideRejection || downsideRejection;
      
      if(rejected)
      {
         if(!lastTestWasRejection)
         {
            testCount++;
            lastTestWasRejection = true;
         }
      }
      else
      {
         lastTestWasRejection = false;
      }
   }
   return testCount;
}

//+------------------------------------------------------------------+
//| Draw confluence line on chart                                    |
//+------------------------------------------------------------------+
void DrawConfluenceLine(double price, int sources, int testCount, double currentPrice)
{
   double normalizedPrice = NormalizeDouble(price, Digits);
   string name = levelPrefix + DoubleToString(normalizedPrice, Digits);
   color lineColor = (currentPrice > normalizedPrice) ? SupportColor : ResistanceColor;
   int lineStyle = (testCount > 2) ? STYLE_SOLID : STYLE_DOT;
   int width = (testCount > 3) ? LineWidth + 1 : LineWidth;
   
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, normalizedPrice);
      ObjectSetInteger(0, name, OBJPROP_COLOR, lineColor);
      ObjectSetInteger(0, name, OBJPROP_STYLE, lineStyle);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      
      string sourceText = GetSourceText(sources);
      string desc = name + "_desc";
      string labelText = StringFormat("%s (%d tests)", sourceText, testCount);
      
      int labelShift = MathMin(10, Bars-1);
      datetime labelTime = Time[labelShift];
      
      ObjectCreate(0, desc, OBJ_TEXT, 0, labelTime, normalizedPrice);
      ObjectSetString(0, desc, OBJPROP_TEXT, labelText);
      ObjectSetInteger(0, desc, OBJPROP_COLOR, lineColor);
      ObjectSetInteger(0, desc, OBJPROP_ANCHOR, ANCHOR_LEFT);
      ObjectSetInteger(0, desc, OBJPROP_BACK, true);
   }
}

//+------------------------------------------------------------------+
//| Generate source description text                                 |
//+------------------------------------------------------------------+
string GetSourceText(int sources)
{
   string text = "";
   
   if((sources & 1) != 0) text += "Round ";
   if((sources & 2) != 0) text += "Swing ";
   if((sources & 4) != 0) text += "Fib ";
   
   return StringTrimRight(text);
}

//+------------------------------------------------------------------+
//| Update line colors based on price position                       |
//+------------------------------------------------------------------+
void UpdateLineColors(double currentPrice)
{
   int total = ObjectsTotal(0, -1);
   for(int i = total-1; i >= 0; i--)
   {
      string name = ObjectName(0, i);
      if(StringFind(name, levelPrefix) == 0)
      {
         double price = ObjectGetDouble(0, name, OBJPROP_PRICE1);
         color lineColor = (currentPrice > price) ? SupportColor : ResistanceColor;
         ObjectSetInteger(0, name, OBJPROP_COLOR, lineColor);
         
         string desc = name + "_desc";
         if(ObjectFind(0, desc) >= 0)
         {
            ObjectSetInteger(0, desc, OBJPROP_COLOR, lineColor);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Delete all confluence lines                                      |
//+------------------------------------------------------------------+
void DeleteAllConfluenceLines()
{
   int total = ObjectsTotal(0, -1);
   for(int i = total-1; i >= 0; i--)
   {
      string name = ObjectName(0, i);
      if(StringFind(name, levelPrefix) == 0)
      {
         ObjectDelete(0, name);
         ObjectDelete(0, name + "_desc");
      }
   }
}

//+------------------------------------------------------------------+
//| Check if bar is a swing high                                     |
//+------------------------------------------------------------------+
bool IsSwingHigh(int bar, int lookback, const double &high[], int rates_total)
{
   if(bar < lookback || bar >= rates_total - lookback) return false;
   
   for(int i = 1; i <= lookback; i++)
   {
      if(high[bar] <= high[bar-i] || high[bar] <= high[bar+i]) 
         return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Check if bar is a swing low                                      |
//+------------------------------------------------------------------+
bool IsSwingLow(int bar, int lookback, const double &low[], int rates_total)
{
   if(bar < lookback || bar >= rates_total - lookback) return false;
   
   for(int i = 1; i <= lookback; i++)
   {
      if(low[bar] >= low[bar-i] || low[bar] >= low[bar+i]) 
         return false;
   }
   return true;
}
//+------------------------------------------------------------------+