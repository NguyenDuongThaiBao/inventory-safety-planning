CREATE OR ALTER PROCEDURE dbo.usp_Load_FactSnapshot
AS
BEGIN
    DECLARE @last   DATETIME = (SELECT LastLoadDate FROM dbo.ETL_Watermark
                                WHERE TableName = 'ProductInventory');
    DECLARE @maxMod DATETIME = (SELECT MAX(ModifiedDate)
                                FROM CompanyX.Production.ProductInventory);
    DECLARE @rows INT = 0, @dateKey INT, @snapDate DATE;
 
    IF @maxMod IS NULL OR @maxMod <= @last
    BEGIN
        INSERT dbo.ETL_Log (StepName, RowsAffected, Status, Message)
        VALUES ('4. FactInventorySnapshot', 0, 'SUCCESS',
                'No changes since last run (incremental)');
        RETURN;
    END
 
    SET @snapDate = CAST(@maxMod AS DATE);
    SET @dateKey  = CONVERT(INT, FORMAT(@maxMod, 'yyyyMMdd'));
    DELETE FROM dbo.FactInventorySnapshot WHERE DateKey = @dateKey;
 
    INSERT dbo.FactInventorySnapshot
        (DateKey, ProductKey, LocationKey, Quantity, QtyBelowSafety,
         InventoryValue, DaysOfSupply, IsStockout, StockStatus)
    SELECT @dateKey, dp.ProductKey, dl.LocationKey, pi.Quantity,
        CASE WHEN dp.SafetyStockLevel > pi.Quantity
             THEN dp.SafetyStockLevel - pi.Quantity ELSE 0 END,
        pi.Quantity * dp.StandardCost,
        ... ,
        CASE WHEN pi.Quantity = 0 THEN 1 ELSE 0 END,
        CASE WHEN pi.Quantity = 0                   THEN 'Stockout'
             WHEN pi.Quantity < dp.SafetyStockLevel THEN 'Below safety stock'
             WHEN pi.Quantity < dp.ReorderPoint     THEN 'Below reorder point'
             ELSE 'OK' END
    FROM CompanyX.Production.ProductInventory pi
    /* date-correct lookup: the version valid on the snapshot date */
    JOIN dbo.DimProduct  dp ON dp.ProductID  = pi.ProductID
                           AND @snapDate BETWEEN dp.EffectiveDate
                                             AND ISNULL(dp.ExpiryDate,'9999-12-31')
    JOIN dbo.DimLocation dl ON dl.LocationID = pi.LocationID;
    ...
END
