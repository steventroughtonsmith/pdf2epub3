//
//  renderer.m
//  pdf2epub3
//
//  Created by Steven Troughton-Smith on 28/04/2016.
//  Copyright © 2016 High Caffeine Content. All rights reserved.
//
//  Referenced projects: https://github.com/nesium/cocoaheads_pdfscanner_demo
//                       https://github.com/nesium/NSMPDFKit
//

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

CGContextRef pageContext = nil;
CGSize documentSize = (CGSize){0,0};
NSMutableString *_currentInFlightHTMLString = nil;

CGColorSpaceRef _strokeColorSpace;
CGColorSpaceRef _fillColorSpace;

static void popFloats(CGPDFScannerRef scanner, CGFloat *buffer, NSUInteger count)
{
	for (NSInteger i = count - 1; i >= 0; i--){
		CGPDFReal value;
		if (!CGPDFScannerPopNumber(scanner, &value)){
		}
		buffer[i] = value;
	}
}

static CGPoint popPoint(CGPDFScannerRef scanner)
{
	CGFloat values[2];
	popFloats(scanner, values, 2);
	return *((CGPoint *)values);
}

static CGAffineTransform popMatrix(CGPDFScannerRef scanner)
{
	CGFloat values[6];
	popFloats(scanner, values, 6);
	return *((CGAffineTransform *)values);
}

static CGColorSpaceRef createColorSpaceWithName(const char *name, void *userInfo)
{
	if (strcmp(name, "DeviceGray") == 0) {
		return CGColorSpaceCreateDeviceGray();
	} else if (strcmp(name, "DeviceRGB") == 0) {
		return CGColorSpaceCreateDeviceRGB();
	} else if (strcmp(name, "DeviceCMYK") == 0) {
		return CGColorSpaceCreateDeviceCMYK();
	} else if (strcmp(name, "Pattern") == 0) {
		CGColorSpaceRef rgbColorSpace = CGColorSpaceCreateDeviceRGB();
		CGColorSpaceRef colorSpace = CGColorSpaceCreatePattern(rgbColorSpace);
		CGColorSpaceRelease(rgbColorSpace);
		return colorSpace;
	} else {
		return CGColorSpaceCreateDeviceRGB();
	}
}

static CGColorRef createColorUsingColorSpace(CGPDFScannerRef scanner,
											 CGColorSpaceRef colorSpace) {
	CGColorSpaceModel model = CGColorSpaceGetModel(colorSpace);
	
	switch (model) {
		case kCGColorSpaceModelRGB: {
			CGFloat rgb[3];
			popFloats(scanner, rgb, 3);
			return CGColorCreate(colorSpace, (CGFloat[4]){rgb[0], rgb[1], rgb[2], 1.0f});
		} case kCGColorSpaceModelDeviceN: {
			NSLog(@"DeviceN ColorSpace not supported");
			break;
		} case kCGColorSpaceModelCMYK: {
			CGFloat cmyk[3];
			popFloats(scanner, cmyk, 4);
			return CGColorCreate(colorSpace, cmyk);
		} case kCGColorSpaceModelIndexed: {
			NSLog(@"Indexed ColorSpace not supported");
			break;
		} case kCGColorSpaceModelLab: {
			NSLog(@"Lab ColorSpace not supported");
			break;
		} case kCGColorSpaceModelMonochrome: {
			NSLog(@"Monochrome ColorSpace not supported");
			break;
		} case kCGColorSpaceModelPattern: {
			NSLog(@"Pattern ColorSpace not supported");
			break;
		} case kCGColorSpaceModelUnknown: {
			NSLog(@"Ingoring unknown ColorSpace");
		}
	}
	return NULL;
}

static void op_q(CGPDFScannerRef s, void *info) {
	CGContextSaveGState(pageContext);
}

static void op_Q(CGPDFScannerRef s, void *info) {
	CGContextRestoreGState(pageContext);
}

static void op_cm(CGPDFScannerRef scanner, void *info)
{
	CGAffineTransform transform = popMatrix(scanner);
	CGContextConcatCTM(pageContext, transform);
}

static void op_m(CGPDFScannerRef scanner, void *info)
{
	CGPoint p = popPoint(scanner);
	
	CGContextBeginPath(pageContext);
	CGContextMoveToPoint(pageContext, p.x, p.y);
}

static void op_l(CGPDFScannerRef scanner, void *info)
{
	CGPoint p = popPoint(scanner);
	
	CGContextAddLineToPoint(pageContext, p.x, p.y);
}

static void op_f(CGPDFScannerRef scanner, void *info)
{
	CGContextFillPath(pageContext);
}

static void op_fstar(CGPDFScannerRef scanner, void *info)
{
	CGContextEOFillPath(pageContext);
}

static void op_c(CGPDFScannerRef scanner, void *info)
{
	CGPoint p = popPoint(scanner);
	CGPoint cp2 = popPoint(scanner);
	CGPoint cp1 = popPoint(scanner);
	CGContextAddCurveToPoint(pageContext, cp1.x, cp1.y, cp2.x, cp2.y, p.x, p.y);
}

static void op_W(CGPDFScannerRef scanner, void *info)
{
	CGContextClip(pageContext);
}

static void op_w(CGPDFScannerRef scanner, void *info)
{
	CGFloat width = 0.0;
	CGPDFScannerPopNumber(scanner, &width);
	
	CGContextSetLineWidth(pageContext, width);
}

static void op_Wstar(CGPDFScannerRef scanner, void *info)
{
	CGContextEOClip(pageContext);
}

static void op_j(CGPDFScannerRef scanner, void *info)
{
	CGPDFReal join = 0;
	CGPDFScannerPopNumber(scanner, &join);
	
	CGContextSetLineJoin(pageContext, join);
	
}


static void op_J(CGPDFScannerRef scanner, void *info)
{
	CGPDFReal cap = 0;
	CGPDFScannerPopNumber(scanner, &cap);
	
	CGContextSetLineCap(pageContext, cap);
}


static void op_M(CGPDFScannerRef scanner, void *info)
{
	CGPDFReal miter = 0;
	CGPDFScannerPopNumber(scanner, &miter);
	
	CGContextSetMiterLimit(pageContext, miter);
	
}

static void op_ri(CGPDFScannerRef scanner, void *info)
{
	CGPDFReal intent = 0;
	CGPDFScannerPopNumber(scanner, &intent);
	
	CGContextSetRenderingIntent(pageContext, intent);
	
}

static void op_re(CGPDFScannerRef scanner, void *info)
{
	CGFloat values[4];
	popFloats(scanner, values, 4);
	CGRect rect = *((CGRect *)values);
	CGContextAddRect(pageContext, rect);
}

static void op_g(CGPDFScannerRef scanner, void *info)
{
	
}

static void op_G(CGPDFScannerRef scanner, void *info)
{
	
}

static void op_rg(CGPDFScannerRef scanner, void *info)
{
	CGFloat rgb[3];
	popFloats(scanner, rgb, 3);
	CGColorRef color = CGColorCreateGenericRGB(rgb[0], rgb[1], rgb[2], 1.0f);
	CGContextSetFillColorWithColor(pageContext, color);
	CGColorRelease(color);
}

static void op_RG(CGPDFScannerRef scanner, void *info)
{
	CGFloat rgb[3];
	popFloats(scanner, rgb, 3);
	CGColorRef color = CGColorCreateGenericRGB(rgb[0], rgb[1], rgb[2], 1.0f);
	CGContextSetStrokeColorWithColor(pageContext, color);
	CGColorRelease(color);
}

static void op_n(CGPDFScannerRef scanner, void *info)
{
	if (!CGContextIsPathEmpty(pageContext)) // omit CG warning
		CGContextClosePath(pageContext);
}

static void op_h(CGPDFScannerRef scanner, void *info)
{
	if (!CGContextIsPathEmpty(pageContext)) // omit CG warning
		
		CGContextClosePath(pageContext);
}

static void op_S(CGPDFScannerRef scanner, void *info)
{
	CGContextStrokePath(pageContext);
}

static void op_s(CGPDFScannerRef scanner, void *info)
{
	if (!CGContextIsPathEmpty(pageContext)) // omit CG warning
		CGContextClosePath(pageContext);
	
	CGContextStrokePath(pageContext);
}


static void op_cs(CGPDFScannerRef scanner, void *info)
{
	const char *name;
	if (!CGPDFScannerPopName(scanner, &name)) {
		return;
	}
	_fillColorSpace = createColorSpaceWithName(name, info);
	CGContextSetFillColorSpace(pageContext, _fillColorSpace);
}


static void op_CS(CGPDFScannerRef scanner, void *info)
{
	const char *name;
	if (!CGPDFScannerPopName(scanner, &name)) {
		return;
	}
	_strokeColorSpace = createColorSpaceWithName(name, info);
	CGContextSetStrokeColorSpace(pageContext, _strokeColorSpace);
}

static void op_i(CGPDFScannerRef scanner, void *info)
{
	CGPDFReal flatness = 0;
	CGPDFScannerPopNumber(scanner, &flatness);
	
	CGContextSetFlatness(pageContext, flatness);
}

static void op_y(CGPDFScannerRef scanner, void *info)
{
	CGPoint p = popPoint(scanner);
	CGPoint cp2 = p;
	CGPoint cp1 = popPoint(scanner);
	
	CGContextAddCurveToPoint(pageContext, cp1.x, cp1.y, cp2.x, cp2.y, p.x, p.y);
}

static void op_v(CGPDFScannerRef scanner, void *info)
{
	CGPoint cp1 = CGContextGetPathCurrentPoint(pageContext);
	CGPoint p = popPoint(scanner);
	CGPoint cp2 = popPoint(scanner);
	CGContextAddCurveToPoint(pageContext, cp1.x, cp1.y, cp2.x, cp2.y, p.x, p.y);
}

static void op_SC(CGPDFScannerRef scanner, void *info)
{
	CGFloat rgb[3];
	popFloats(scanner, rgb, 3);
	CGColorRef color = CGColorCreateGenericRGB(rgb[0], rgb[1], rgb[2], 1.0f);
	CGContextSetStrokeColorWithColor(pageContext, color);
	CGColorRelease(color);
}

static void op_sc(CGPDFScannerRef scanner, void *info)
{
	CGFloat rgb[3];
	popFloats(scanner, rgb, 3);
	CGColorRef color = CGColorCreateGenericRGB(rgb[0], rgb[1], rgb[2], 1.0f);
	CGContextSetFillColorWithColor(pageContext, color);
	CGColorRelease(color);
}

static void op_SCN(CGPDFScannerRef scanner, void *info)
{
	CGColorRef color = createColorUsingColorSpace(scanner, _strokeColorSpace);
	CGContextSetStrokeColorWithColor(pageContext, color);
	CGColorRelease(color);
}

static void op_scn(CGPDFScannerRef scanner, void *info)
{
	CGColorRef color = createColorUsingColorSpace(scanner, _fillColorSpace);
	CGContextSetFillColorWithColor(pageContext, color);
	CGColorRelease(color);
}

static void op_b(CGPDFScannerRef scanner, void *info)
{
	if (!CGContextIsPathEmpty(pageContext)) // omit CG warning
		CGContextClosePath(pageContext);
	
	CGContextFillPath(pageContext);
	CGContextStrokePath(pageContext);
}
static void op_B(CGPDFScannerRef scanner, void *info)
{
	CGContextFillPath(pageContext);
	CGContextStrokePath(pageContext);
	
}
static void op_bstar(CGPDFScannerRef scanner, void *info)
{
	if (!CGContextIsPathEmpty(pageContext)) // omit CG warning
		CGContextClosePath(pageContext);
	
	CGContextEOFillPath(pageContext);
	CGContextStrokePath(pageContext);
	
}
static void op_Bstar(CGPDFScannerRef scanner, void *info)
{
	CGContextEOFillPath(pageContext);
	CGContextStrokePath(pageContext);
	
}

static void op_d(CGPDFScannerRef scanner, void *info)
{
	CGPDFArrayRef dashArray;
	CGFloat dashPhase;
	if (!CGPDFScannerPopNumber(scanner, &dashPhase)) {
		return;
	}
	if (!CGPDFScannerPopArray(scanner, &dashArray)) {
		return;
	}
	
	size_t count = CGPDFArrayGetCount(dashArray);
	
	if (count == 0) {
		return;
	}
	
	CGFloat *lengths = malloc(sizeof(CGFloat) * count);
	for (size_t i = 0; i < count; i++) {
		CGPDFArrayGetNumber(dashArray, i, &lengths[i]);
	}
	CGContextSetLineDash(pageContext, dashPhase, lengths, count);
	free(lengths);
}


static void op_K(CGPDFScannerRef scanner, void *info)
{
	printf("op_K\n");
}
static void op_k(CGPDFScannerRef scanner, void *info)

{
	printf("op_k\n");
}


CGFloat *decodeValuesFromImageDictionary(CGPDFDictionaryRef dict, CGColorSpaceRef cgColorSpace, NSInteger bitsPerComponent) {
	CGFloat *decodeValues = NULL;
	CGPDFArrayRef decodeArray = NULL;
	
	if (CGPDFDictionaryGetArray(dict, "Decode", &decodeArray)) {
		size_t count = CGPDFArrayGetCount(decodeArray);
		decodeValues = malloc(sizeof(CGFloat) * count);
		CGPDFReal realValue;
		int i;
		for (i = 0; i < count; i++) {
			CGPDFArrayGetNumber(decodeArray, i, &realValue);
			decodeValues[i] = realValue;
		}
	} else {
		size_t n;
		switch (CGColorSpaceGetModel(cgColorSpace)) {
			case kCGColorSpaceModelMonochrome:
				decodeValues = malloc(sizeof(CGFloat) * 2);
				decodeValues[0] = 0.0;
				decodeValues[1] = 1.0;
				break;
			case kCGColorSpaceModelRGB:
				decodeValues = malloc(sizeof(CGFloat) * 6);
				for (int i = 0; i < 6; i++) {
					decodeValues[i] = i % 2 == 0 ? 0 : 1;
				}
				break;
			case kCGColorSpaceModelCMYK:
				decodeValues = malloc(sizeof(CGFloat) * 8);
				for (int i = 0; i < 8; i++) {
					decodeValues[i] = i % 2 == 0 ? 0.0 :
					1.0;
				}
				break;
			case kCGColorSpaceModelLab:
				// ????
				break;
			case kCGColorSpaceModelDeviceN:
				n =
				CGColorSpaceGetNumberOfComponents(cgColorSpace) * 2;
				decodeValues = malloc(sizeof(CGFloat) * (n *
														 2));
				for (int i = 0; i < n; i++) {
					decodeValues[i] = i % 2 == 0 ? 0.0 :
					1.0;
				}
				break;
			case kCGColorSpaceModelIndexed:
				decodeValues = malloc(sizeof(CGFloat) * 2);
				decodeValues[0] = 0.0;
				decodeValues[1] = pow(2.0,
									  (double)bitsPerComponent) - 1;
				break;
			default:
				break;
		}
	}
	
	return (CGFloat *)decodeValues;
}

// temporary C function to print out keys
void printPDFKeys(const char *key, CGPDFObjectRef ob, void *info) {
	NSLog(@"key = %s", key);
}

static void op_Do(CGPDFScannerRef s, void *info) {
	const char *imageLabel;
 
	if (!CGPDFScannerPopName(s, &imageLabel)) {
		return;
	}
	
	CGPDFContentStreamRef cs = CGPDFScannerGetContentStream(s);
	CGPDFObjectRef imageObject = CGPDFContentStreamGetResource(cs, "XObject", imageLabel);
	CGPDFStreamRef xObjectStream;
	if (CGPDFObjectGetValue(imageObject, kCGPDFObjectTypeStream, &xObjectStream)) {
		
		CGPDFDictionaryRef xObjectDictionary = CGPDFStreamGetDictionary(xObjectStream);
		
		const char *subtype;
		CGPDFDictionaryGetName(xObjectDictionary, "Subtype", &subtype);
		if (strcmp(subtype, "Image") == 0) {
			
#if 0
			CGPoint vertices[4];
			
			// Transform the image coordinates into page coordinates based on current transformation matrix.
			vertices[0] = CGPointApplyAffineTransform(CGPointMake(0, 0), ctm); // lower left
			vertices[1] = CGPointApplyAffineTransform(CGPointMake(1, 0), ctm); // lower right
			vertices[2] = CGPointApplyAffineTransform(CGPointMake(1, 1), ctm); // upper right
			vertices[3] = CGPointApplyAffineTransform(CGPointMake(0, 1), ctm); // upper left
			
			
			
			// Vertices 0 and 1 define the horizontal, vertices 1 and 2 define the vertical.
			CGFloat displayWidth = sqrt((vertices[0].x - vertices[1].x) * (vertices[0].x - vertices[1].x) +
										(vertices[0].y - vertices[1].y) * (vertices[0].y - vertices[1].y));
			CGFloat displayHeight = sqrt((vertices[1].x - vertices[2].x) * (vertices[1].x - vertices[2].x) +
										 (vertices[1].y - vertices[2].y) * (vertices[1].y - vertices[2].y));
			
#endif
			
			CGPDFInteger pixelWidth;
			if (CGPDFDictionaryGetInteger(xObjectDictionary, "Width", &pixelWidth)) {
			}
			CGPDFInteger pixelHeight;
			if (CGPDFDictionaryGetInteger(xObjectDictionary, "Height", &pixelHeight)) {
			}
			
			CGPDFInteger bitsPerComponent;
			if (CGPDFDictionaryGetInteger(xObjectDictionary, "BitsPerComponent", &bitsPerComponent)) {
			}
			
			//CGPDFDictionaryApplyFunction(xObjectDictionary, printPDFKeys, NULL);
			
			CGPDFDataFormat format;
			CFDataRef data = CGPDFStreamCopyData (xObjectStream, &format);
			
			if (format == CGPDFDataFormatJPEGEncoded)
			{
				NSImage *img = [[NSImage alloc] initWithData:(__bridge NSData * _Nonnull)(data)];
				
				[img drawInRect:CGRectMake(0, 0, 1.0, 1.0) fromRect:CGRectZero operation:NSCompositeSourceOver fraction:1.0];
			}
			
			CFRelease(data);
		}
		else {
			
		}
	}
 
}

#pragma mark -

CGFloat _leading = 0.0;
CGFloat textSpacing = 0;
CGFloat wordSpacing = 0;
CGAffineTransform lineMatrix;

static void op_BT(CGPDFScannerRef scanner, void *info)
{
	CGContextSetTextMatrix(pageContext, CGAffineTransformIdentity);
	_leading = 0;
}

static void op_ET(CGPDFScannerRef scanner, void *info)
{
	
}


NSDictionary *_currentFontAttribs = nil;

static void op_Tf(CGPDFScannerRef scanner, void *info)
{
	CGPDFReal fontSize;
	if (!CGPDFScannerPopNumber(scanner, &fontSize)){
		NSLog(@"Could not pop font size");
		return;
	}
	
	const char *fontName;
	if (!CGPDFScannerPopName(scanner, &fontName)){
		NSLog(@"Could not pop font name");
	}
	
	/*
	 NSMPDFFont *font = [(NSMPDFPage *)info fontForKey:fontName];
	 font.size = fontSize;
	 ((NSMPDFPage *)info).context.font = font;
	 CGContextSetFont(NSM_CTX(info), font.CGFont);
	 CGContextSetFontSize(NSM_CTX(info), fontSize);
	 */
	
	NSLog(@"Font = %@", [NSString stringWithUTF8String:fontName]);
	
	if (fontSize == 1.0)
		fontSize = 16;
	
	NSFont *font = [NSFont fontWithName:[NSString stringWithUTF8String:fontName] size:fontSize ];
	
	if (!font)
	{
		font = [NSFont systemFontOfSize:fontSize];
	}
	
	_currentFontAttribs = @{
							NSFontAttributeName:font
							};
}


static void op_Tj(CGPDFScannerRef scanner, void *info)
{
	CGPDFStringRef str;
	if (!CGPDFScannerPopString(scanner, &str)){
		NSLog(@"Could not pop string");
		return;
	}

	const char *text = (const char *)CGPDFStringGetBytePtr(str);
	size_t textLen = CGPDFStringGetLength(str);
	
	CGPoint pos = CGContextGetTextPosition(pageContext);
	
	NSString *string = [NSString stringWithUTF8String:text];
	CGFloat width = ([string sizeWithAttributes:_currentFontAttribs].width)/2;
	
	[_currentInFlightHTMLString appendFormat:@"<div style='font-family: Times; font-size: %fpx; position: absolute; left: %.2fpx; top: %.2fpx; width: %.2fpx;'>%@</div>",[_currentFontAttribs[NSFontAttributeName] pointSize], pos.x*2, (documentSize.height-pos.y*2), width*2, string];
	
	pos.x += width+wordSpacing+textSpacing*textLen;
	
	CGContextSetTextPosition(pageContext, pos.x, pos.y);
}

static void op_TJ(CGPDFScannerRef scanner, void *info)
{
	CGPDFArrayRef entries;
	if (!CGPDFScannerPopArray(scanner, &entries)){
		NSLog(@"Could not pop text array");
		return;
	}
	
	CGContextRef ctx = pageContext;
	
	size_t count = CGPDFArrayGetCount(entries);
	for (size_t i = 0; i < count; i++){
		CGPDFObjectRef entry;
		CGPDFArrayGetObject(entries, i, &entry);
		
		if (CGPDFObjectGetType(entry) == kCGPDFObjectTypeString){
			CGPDFStringRef str;
			CGPDFObjectGetValue(entry, kCGPDFObjectTypeString, &str);
			
			const char *text = (const char *)CGPDFStringGetBytePtr(str);
			size_t textLen = CGPDFStringGetLength(str);
			

			CGPoint pos = CGContextGetTextPosition(pageContext);

			for (int i = 0; i<textLen; i++)
				
			{
				NSString *string = [NSString stringWithFormat:@"%c", text[i]];
				
				CGFloat width = ([string sizeWithAttributes:_currentFontAttribs].width)/2;
				
				[_currentInFlightHTMLString appendFormat:@"<div style='font-family: Times; font-size: %fpx; position: absolute; left: %.2fpx; top: %.2fpx; width: %.2fpx;'>%c</div>",[_currentFontAttribs[NSFontAttributeName] pointSize], pos.x*2, (documentSize.height-pos.y*2), width*2, text[i]];
				
				pos.x += width + textSpacing;
			}
			
			pos.x += wordSpacing;
			
			CGContextSetTextPosition(pageContext, pos.x, pos.y);
		}
		else
		{
			CGPDFReal offset;
			CGPDFObjectGetValue(entry, kCGPDFObjectTypeReal, &offset);
			CGPoint pos = CGContextGetTextPosition(ctx);
			pos.x -= offset / 1000.0f;
			CGContextSetTextPosition(ctx, pos.x, pos.y);
		}
	}
}

static void op_Td(CGPDFScannerRef scanner, void *info)
{
	CGPoint offset = popPoint(scanner);
	
	lineMatrix = CGAffineTransformTranslate(lineMatrix, offset.x, offset.y);
	
	CGContextSetTextMatrix(pageContext, lineMatrix);
}

static void op_TD(CGPDFScannerRef scanner, void *info)
{
	CGPoint offset = popPoint(scanner);
	
	lineMatrix = CGAffineTransformTranslate(lineMatrix, offset.x, offset.y);
	_leading = offset.y;
	
	CGContextSetTextMatrix(pageContext, lineMatrix);
}

static void op_Tstar(CGPDFScannerRef scanner, void *info)
{
	lineMatrix = CGAffineTransformTranslate(lineMatrix, 0, _leading);
	CGContextSetTextMatrix(pageContext, lineMatrix);
}

static void op_Tm(CGPDFScannerRef scanner, void *info)
{
	CGAffineTransform transform = popMatrix(scanner);
	lineMatrix = transform;
	CGContextSetTextMatrix(pageContext, transform);
}

static void op_TL(CGPDFScannerRef scanner, void *info)
{
	CGPDFReal leading;
	if (!CGPDFScannerPopNumber(scanner, &leading)){
		NSLog(@"Could not pop font size");
		return;
	}
	
	CGAffineTransform textMatrix = CGContextGetTextMatrix(pageContext);
	textMatrix = CGAffineTransformTranslate(textMatrix, 0, leading);
	_leading = leading;
	
	CGContextSetTextMatrix(pageContext, textMatrix);
}


static void op_Tc(CGPDFScannerRef scanner, void *info)
{
	CGPDFReal spacing;
	if (!CGPDFScannerPopNumber(scanner, &spacing)){
		NSLog(@"Could not pop font size");
		return;
	}
	
	textSpacing = spacing;
}

static void op_Tw(CGPDFScannerRef scanner, void *info)
{
	CGPDFReal spacing;
	if (!CGPDFScannerPopNumber(scanner, &spacing)){
		NSLog(@"Could not pop font size");
		return;
	}
	
	wordSpacing = spacing;
}

#pragma mark -

void beginPDFPageScan(CGPDFPageRef page)
{
	CGPDFContentStreamRef contentStream = CGPDFContentStreamCreateWithPage(page);
	CGPDFOperatorTableRef operatorTable = CGPDFOperatorTableCreate();
	
	/* Functions */
	CGPDFOperatorTableSetCallback(operatorTable, "q", &op_q);
	CGPDFOperatorTableSetCallback(operatorTable, "Q", &op_Q);
	
	CGPDFOperatorTableSetCallback(operatorTable, "rg", &op_rg);
	CGPDFOperatorTableSetCallback(operatorTable, "RG", &op_RG);
	
	CGPDFOperatorTableSetCallback(operatorTable, "sc", &op_sc);
	CGPDFOperatorTableSetCallback(operatorTable, "SC", &op_SC);
	
	CGPDFOperatorTableSetCallback(operatorTable, "scn", &op_scn);
	CGPDFOperatorTableSetCallback(operatorTable, "SCN", &op_SCN);
	
	CGPDFOperatorTableSetCallback(operatorTable, "k", &op_k);
	CGPDFOperatorTableSetCallback(operatorTable, "K", &op_K);
	
	CGPDFOperatorTableSetCallback(operatorTable, "cm", &op_cm);
	
	/* Path Operators */
	
	CGPDFOperatorTableSetCallback(operatorTable, "m", &op_m);
	CGPDFOperatorTableSetCallback(operatorTable, "l", &op_l);
	CGPDFOperatorTableSetCallback(operatorTable, "f", &op_f);
	CGPDFOperatorTableSetCallback(operatorTable, "F", &op_f);
	CGPDFOperatorTableSetCallback(operatorTable, "f*", &op_fstar);
	
	CGPDFOperatorTableSetCallback(operatorTable, "c", &op_c);
	
	CGPDFOperatorTableSetCallback(operatorTable, "ri", &op_ri);
	
	CGPDFOperatorTableSetCallback(operatorTable, "re", &op_re);
	CGPDFOperatorTableSetCallback(operatorTable, "S", &op_S);
	CGPDFOperatorTableSetCallback(operatorTable, "s", &op_s);
	
	CGPDFOperatorTableSetCallback(operatorTable, "h", &op_h);
	CGPDFOperatorTableSetCallback(operatorTable, "M", &op_M);
	
	CGPDFOperatorTableSetCallback(operatorTable, "b", &op_b);
	CGPDFOperatorTableSetCallback(operatorTable, "B", &op_B);
	CGPDFOperatorTableSetCallback(operatorTable, "b*", &op_bstar);
	CGPDFOperatorTableSetCallback(operatorTable, "B*", &op_Bstar);
	
	CGPDFOperatorTableSetCallback(operatorTable, "d", &op_d);
	
	CGPDFOperatorTableSetCallback(operatorTable, "j", &op_j);
	CGPDFOperatorTableSetCallback(operatorTable, "J", &op_J);
	
	CGPDFOperatorTableSetCallback(operatorTable, "g", &op_g);
	CGPDFOperatorTableSetCallback(operatorTable, "G", &op_G);
	
	CGPDFOperatorTableSetCallback(operatorTable, "i", &op_i);
	
	CGPDFOperatorTableSetCallback(operatorTable, "y", &op_y);
	CGPDFOperatorTableSetCallback(operatorTable, "v", &op_v);
	
	CGPDFOperatorTableSetCallback(operatorTable, "n", &op_n);
	CGPDFOperatorTableSetCallback(operatorTable, "w", &op_w);
	CGPDFOperatorTableSetCallback(operatorTable, "W", &op_W);
	CGPDFOperatorTableSetCallback(operatorTable, "W*", &op_Wstar);
	
	CGPDFOperatorTableSetCallback(operatorTable, "cs", &op_cs);
	CGPDFOperatorTableSetCallback(operatorTable, "CS", &op_CS);
	
	/* Image Operators */
	
	CGPDFOperatorTableSetCallback(operatorTable, "Do", &op_Do);
	
	/* Text Operators */
	
	CGPDFOperatorTableSetCallback(operatorTable, "BT", &op_BT);
	CGPDFOperatorTableSetCallback(operatorTable, "ET", &op_ET);
	
	CGPDFOperatorTableSetCallback(operatorTable, "Tf", &op_Tf);
	
	
	CGPDFOperatorTableSetCallback(operatorTable, "Tj", &op_Tj);
	CGPDFOperatorTableSetCallback(operatorTable, "TJ", &op_TJ);
	
	CGPDFOperatorTableSetCallback(operatorTable, "TL", &op_TL);
	
	CGPDFOperatorTableSetCallback(operatorTable, "Tm", &op_Tm);
	
	CGPDFOperatorTableSetCallback(operatorTable, "Tc", &op_Tc);
	CGPDFOperatorTableSetCallback(operatorTable, "Tw", &op_Tw);
	
	
	CGPDFOperatorTableSetCallback(operatorTable, "Td", &op_Td);
	CGPDFOperatorTableSetCallback(operatorTable, "TD", &op_TD);
	CGPDFOperatorTableSetCallback(operatorTable, "T*", &op_Tstar);
	
 
	CGPDFScannerRef contentStreamScanner = CGPDFScannerCreate(contentStream, operatorTable, nil);
	CGPDFScannerScan(contentStreamScanner);
 
	CGPDFScannerRelease(contentStreamScanner);
	CGPDFOperatorTableRelease(operatorTable);
	
	CGPDFContentStreamRelease(contentStream);
}

NSImage *renderImageForPageOfPDF(NSUInteger pageNumber, CGPDFDocumentRef pdf, BOOL rasterize)
{
	CGPDFPageRef page = CGPDFDocumentGetPage(pdf, pageNumber);
	
	if (!page)
	{
		CGPDFDocumentRelease(pdf);
		return [[NSImage alloc] initWithSize:CGSizeZero];
	}
	
	CGRect cropBoxRect = CGPDFPageGetBoxRect(page, kCGPDFCropBox);
	CGRect mediaBoxRect = CGPDFPageGetBoxRect(page, kCGPDFMediaBox);
	
	CGFloat scaleFactor = 1366/cropBoxRect.size.height;
	CGFloat scaledCropWidth = cropBoxRect.size.width*scaleFactor;
	
	CGSize imageSize = cropBoxRect.size;
	
	if (rasterize)
	{
		imageSize = CGSizeMake(scaledCropWidth, 1366);
	}
		
	NSImage *img = [[NSImage alloc] initWithSize:imageSize];
	
	documentSize = CGSizeMake(img.size.width*[NSScreen mainScreen].backingScaleFactor, img.size.height*[NSScreen mainScreen].backingScaleFactor);
	
	[img lockFocus];
	
	[[NSColor whiteColor] set];
	NSRectFill(CGRectMake(0, 0, img.size.width, img.size.height));
	
	pageContext = [NSGraphicsContext currentContext].graphicsPort;
	
	if (rasterize)
		CGContextScaleCTM(pageContext, scaleFactor, scaleFactor);
	
	CGContextTranslateCTM(pageContext, ((cropBoxRect.size.width-mediaBoxRect.size.width))/2, (cropBoxRect.size.height-mediaBoxRect.size.height)/2);
	
	CGAffineTransform pdfTransform = CGPDFPageGetDrawingTransform(page, kCGPDFCropBox, cropBoxRect, 0, true);
	CGContextConcatCTM(pageContext, pdfTransform);
	
	CGContextClipToRect(pageContext, cropBoxRect);
	
	if (rasterize)
	{
		CGContextDrawPDFPage(pageContext, page);
	}
	else
	{
		_currentInFlightHTMLString = nil;
		_currentInFlightHTMLString = [NSMutableString string];
		
		_currentFontAttribs = @{
								NSFontAttributeName:	[NSFont systemFontOfSize:12]
								};
		
		beginPDFPageScan(page);
	}
	
	
	[img unlockFocus];
		
	return img;
}


NSString *renderTextForPageOfPDF(NSUInteger pageNumber, CGPDFDocumentRef pdf)
{
	
	NSString *returnString = [NSString stringWithString:_currentInFlightHTMLString ? _currentInFlightHTMLString : @""];
	_currentInFlightHTMLString = nil;
	
	return returnString;
}