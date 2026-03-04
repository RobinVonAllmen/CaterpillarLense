// --------- USER PROMPTS: SCALE ---------
open(); // ask user to open the scale image
setTool("line");
waitForUser("Scale: Draw a straight line of known length,\nthen click OK.");
getLine(x1, y1, x2, y2, lineWidth);
pxLen = sqrt((x2-x1)*(x2-x1) + (y2-y1)*(y2-y1));
realLen = getNumber("Enter the real length of the line (in mm):", 10.0);
if (realLen<=0) exit("Real length must be > 0.");

scaleValue = realLen / pxLen;
run("Close");

// --------- PICK A REFERENCE IMAGE AND ENUMERATE SQUARE POSITIONS ---------
open();
setTool("multi");
waitForUser("Define square positions:\nUse the point tool (multipoint) to click the expected square centers in order (1,2,3,...).\nThen click OK.");
getSelectionCoordinates(px, py);
nLayout = px.length;
if (nLayout==0) {
    close();
    exit("No layout points defined.");
}

// store layout positions
layoutX = newArray(nLayout);
layoutY = newArray(nLayout);
for (k=0; k<nLayout; k++) {
    layoutX[k] = px[k];
    layoutY[k] = py[k];
}
run("Close");

// --------- FOLDERS ---------
inDir  = getDirectory("Choose the folder with images to analyze");
outDir = getDirectory("Choose an output folder for results");


// --------- PREPARE ---------
setBatchMode(true);
run("Set Measurements...", "area mean centroid perimeter shape feret redirect=None decimal=5");
if (isOpen("Results")) { selectWindow("Results"); run("Clear Results"); }
roiManager("reset");

resultsFile = outDir + "Caterpillar_Results.csv";
File.delete(resultsFile);
File.append("Image,SquareIndex,ObjectInSquare,Area_px,Area_mm2,Scale,X,Y", resultsFile);

// --------- PROCESS EACH IMAGE ---------
list = getFileList(inDir);

for (i = 0; i < list.length; i++) {
    name = list[i];
    if (!(endsWith(name, ".tif") || endsWith(name, ".tiff") ||
          endsWith(name, ".png") || endsWith(name, ".JPG")  ||
          endsWith(name, ".jpeg")|| endsWith(name, ".bmp"))) continue;

    path = inDir + name;
    open(path);
    origTitle = getTitle();

    // ------------------ FIND HOT-PINK SQUARES ------------------
    run("Duplicate...", "title=__work__");
    selectWindow("__work__");
    run("Despeckle");
    run("HSB Stack");
    run("Stack to Images");
    
    // threshold on Hue (your original used Hue window)
    selectWindow("Hue");
    setThreshold(12, 200);
    run("Convert to Mask");
    run("Invert");
    
    selectWindow("Saturation");
    setThreshold(40, 80);
    run("Convert to Mask");
    
    selectWindow("Brightness");
    setThreshold(0, 255);
    run("Convert to Mask");
    
    imageCalculator("AND create", "Hue","Saturation");
    selectWindow("Result of Hue");
    rename("HS_MASK");
    imageCalculator("AND create", "HS_MASK","Brightness");
    selectWindow("Result of HS_MASK");
    
    setOption("BlackBackground", false);
    rename("__mask_s__");
    run("Close-");
    run("Fill Holes");
    run("Erode");

    // detect the big pink squares
    run("Analyze Particles...", "size=1500000-2000000 circularity=0.00-1.00 show=Nothing display add");
    run("Clear Results");

    nSquares = roiManager("count");
    if (nSquares == 0) {
        // cleanup
        if (isOpen("__mask_s__")) close();
        if (isOpen("Hue")) close();
        if (isOpen("Saturation")) close();
        if (isOpen("Brightness")) close();
        if (isOpen("__work__")) close();
        selectWindow(origTitle); close();
        print("No pink squares found in: " + name);
        roiManager("reset");
        continue;
    }

    // ---- MATCH DETECTED SQUARES TO USER-ENUMERATED POSITIONS ----
    // squareIdx[r] will hold the index (0..nLayout-1) of the closest enumerated point
    squareIdx = newArray(nSquares);
    usedLayout = newArray(nLayout);
    for (u=0; u<nLayout; u++) usedLayout[u] = -1;

    hasDuplicate = false;

    // we need to work on original image to get bounds
    selectWindow(origTitle);
    for (r = 0; r < nSquares; r++) {
    	totResults = 0;
        roiManager("Select", r);
        getSelectionBounds(xr, yr, wr, hr);
        cx = xr + wr/2;
        cy = yr + hr/2;

        // find closest enumerated point
        bestD = -1;
        bestP = -1;
        for (p=0; p<nLayout; p++) {
            dx = cx - layoutX[p];
            dy = cy - layoutY[p];
            d  = sqrt(dx*dx + dy*dy);
            if (bestD<0 || d<bestD) {
                bestD = d;
                bestP = p;
            }
        }

        squareIdx[r] = bestP;
        if (usedLayout[bestP] != -1) {
            hasDuplicate = true;
        } else {
            usedLayout[bestP] = r; // mark this layout point as used
        }
    }

    if (hasDuplicate) {
        print("WARNING: duplicate square match in image " + name + ". Skipping this image.");
        // cleanup
        close("*");
        roiManager("reset");
        continue;
    }

    // ------------------ PROCESS EACH SUB-IMAGE ------------------
    for (r = 0; r < nSquares; r++) {
        selectWindow(origTitle);
        roiManager("Select", r);
        getSelectionBounds(x, y, w, h);

        // crop from original
        makeRectangle(x, y, w, h);
        subTitle = "_sq" + (squareIdx[r]+1);
        saveName = origTitle + subTitle;
        saveName = replace(saveName, ".tif", "");
        saveName = replace(saveName, ".tiff", "");
        saveName = replace(saveName, ".png", "");
        saveName = replace(saveName, ".jpg", "");
        saveName = replace(saveName, ".jpeg", "");
        saveName = replace(saveName, ".bmp", "");
        run("Duplicate...", "title="+subTitle);

        // --- per-subimage workflow ---
        selectWindow(subTitle);
        run("Duplicate...", "title="+subTitle+"_work");
        run("8-bit");
        setThreshold(0, 50);
        setOption("BlackBackground", false);
        run("Convert to Mask");

        // remember how many results we had before analyzing this subimage
        beforeCount = nResults;
        run("Analyze Particles...", "size=640-25000 circularity=0.25-0.9 show=Masks display add");
        rename("mask_" + subTitle);
        run("Invert");

        // go back to subimage to combine
        selectWindow(subTitle);
        imageCalculator("Add create", subTitle, "mask_" + subTitle);
        run("Flatten");

        if(nResults>totResults){
			setFont("SansSerif", 32, "bold");
			setColor("white");
			drawString("Area: " + d2s(getResult("Area", nResults-1)*pow(scaleValue, 2),2) + " mm^2", 50, 100);
		}

        saveAs("PNG", outDir + saveName + "_mask.png");
        close(); // close flattened

        // close originals for this subimage
        if (isOpen(subTitle)) { selectWindow(subTitle); close(); }
        if (isOpen(subTitle+"_work")) { selectWindow(subTitle+"_work"); close(); }
        if (isOpen("mask_" + subTitle)) { selectWindow("mask_" + subTitle); close(); }

        // ---- write out results for THIS subimage only ----
        afterCount = nResults;
        for (rr = beforeCount; rr < afterCount; rr++) {
            imageName = origTitle;
            sqIndex   = squareIdx[r] + 1; // 1-based for the file
            objInSq   = rr - beforeCount + 1; // 1..N objects in that square
            areaPx    = getResult("Area", rr);
            areaMm2   = areaPx * pow(scaleValue, 2);
            xcent     = getResult("X", rr);
            ycent     = getResult("Y", rr);

            line = imageName + "," + sqIndex + "," + objInSq + "," + areaPx + "," + areaMm2 + "," + scaleValue + "," + xcent + "," + ycent;
            File.append(line, resultsFile);
        }
        
        totResults = nResults;
    }

    // ------------------ CLEANUP for this image ------------------
    close("*");
    roiManager("reset");
    
}

// --------- DONE ---------
run("Clear Results");
setBatchMode(false);
print("Finished. Results saved to: " + outDir);
