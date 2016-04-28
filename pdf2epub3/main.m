//
// main.m
// pdf2epub3
//
// Created by Steven Troughton-Smith on 27/04/2016.
// Copyright © 2016 High Caffeine Content. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

#include <getopt.h>

extern CGSize documentSize;
extern CGContextRef pageContext;

NSImage *renderImageForPageOfPDF(NSUInteger pageNumber, CGPDFDocumentRef pdf, BOOL rasterize);
NSString *renderTextForPageOfPDF(NSUInteger pageNumber, CGPDFDocumentRef pdf);

void usage()
{
	printf("usage: pdf2epub3 [-t \"Book Title\"] [-x] file.pdf\n");
}

int main(int argc, const char * argv[]) {
	@autoreleasepool {
				
		NSString *path = nil;

		NSString *uuid = [NSUUID UUID].UUIDString;
		NSString *bookTitle = nil;
		NSString *tmpDir = [NSString stringWithFormat:@"/tmp/%@", uuid];
		NSString *oebpsDir = [tmpDir stringByAppendingPathComponent:@"OEBPS"];
		NSError *error = nil;
		
		NSMutableArray *textSources = [NSMutableArray array];
		BOOL shouldRasterize = YES;
		
		if (argc < 2)
		{
			usage();
			exit(-1);
		}

		int c;
		
		opterr = 0;
		while ((c = getopt (argc, (char *const *)argv, "t:r")) != -1)
			switch (c)
		{
			case 't':
				bookTitle = [NSString stringWithUTF8String:optarg];
				break;
			case 'x':
				shouldRasterize = NO;
				break;
			case '?':
				if (optopt == 't')
				{
					fprintf (stderr, "pdf2epub3: option -%c requires an argument\n", optopt);
					usage();
				}
				else
				{
					usage();
					exit(-1);
				}
				return 1;
			default:
				abort();
		}
		
		if (optind < argc)
		{
			path = [NSString stringWithUTF8String:argv[optind++]];
		}
		
		if (!path || ![[NSFileManager defaultManager] fileExistsAtPath:path])
		{
			usage();
			exit(-1);
		}
		
		bookTitle = path.lastPathComponent.stringByDeletingPathExtension;
		
		NSXMLElement *manifestRoot = (NSXMLElement *)[NSXMLNode elementWithName:@"manifest"];
		NSXMLElement *metadataRoot = (NSXMLElement *)[NSXMLNode elementWithName:@"metadata" children:nil attributes:@[
																													  [NSXMLNode attributeWithName:@"xmlns:dc" stringValue:@"http://purl.org/dc/elements/1.1/"]
																													  ]];
		NSXMLElement *spineRoot = (NSXMLElement *)[NSXMLNode elementWithName:@"spine"];
		
		NSXMLElement *packageRoot = (NSXMLElement *)[NSXMLNode elementWithName:@"package"
																	  children:@[metadataRoot, manifestRoot, spineRoot]
																	attributes:@[
																				 [NSXMLNode attributeWithName:@"prefix" stringValue:@"rendition: http://www.idpf.org/vocab/rendition/# ibooks: http://vocabulary.itunes.apple.com/rdf/ibooks/vocabulary-extensions-1.0/"],
																				 [NSXMLNode attributeWithName:@"xmlns" stringValue:@"http://www.idpf.org/2007/opf"]
																				 ]];
		
		
		[metadataRoot addChild:[NSXMLNode elementWithName:@"meta"
												 children:@[[NSXMLNode textWithStringValue:@"pre-paginated"]]
											   attributes:@[[NSXMLNode attributeWithName:@"property" stringValue:@"rendition:layout"]]]];
		[metadataRoot addChild:[NSXMLNode elementWithName:@"meta"
												 children:@[[NSXMLNode textWithStringValue:@"portrait"]]
											   attributes:@[[NSXMLNode attributeWithName:@"property" stringValue:@"rendition:orientation"]]]];
		[metadataRoot addChild:[NSXMLNode elementWithName:@"meta"
												 children:@[[NSXMLNode textWithStringValue:@"none"]]
											   attributes:@[[NSXMLNode attributeWithName:@"property" stringValue:@"rendition:spread"]]]];
		
		[metadataRoot addChild:[NSXMLNode elementWithName:@"dc:identifier"
												 children:@[[NSXMLNode textWithStringValue:[NSString stringWithFormat:@"urn:uuid:%@", uuid]]]
											   attributes:@[[NSXMLNode attributeWithName:@"id" stringValue:@"bookid"]]]];
		
		[metadataRoot addChild:[NSXMLNode elementWithName:@"dc:title"
												 children:@[[NSXMLNode textWithStringValue:bookTitle]]
											   attributes:@[[NSXMLNode attributeWithName:@"id" stringValue:@"bookid"]]]];
		
		
		[metadataRoot addChild:[NSXMLNode elementWithName:@"meta"
												 children:nil
											   attributes:@[
															[NSXMLNode attributeWithName:@"name" stringValue:@"cover"],
															[NSXMLNode attributeWithName:@"content" stringValue:@"idcover"],
															]]];
		
		
		
		NSXMLDocument *xmlDoc = [[NSXMLDocument alloc] initWithRootElement:packageRoot];
		[xmlDoc setVersion:@"1.0"];
		[xmlDoc setCharacterEncoding:@"UTF-8"];
		
		BOOL didCreate = [[NSFileManager defaultManager] createDirectoryAtPath:oebpsDir withIntermediateDirectories:YES attributes:nil error:&error];
		
		if (error || !didCreate)
		{
			NSLog(@"%@", error.localizedDescription);
			return -1;
		}
		
		/* Images */
		
		
		didCreate = [[NSFileManager defaultManager] createDirectoryAtPath:[oebpsDir stringByAppendingPathComponent:@"Images"] withIntermediateDirectories:YES attributes:nil error:&error];
		
		if (error || !didCreate)
		{
			NSLog(@"%@", error.localizedDescription);
			return -1;
		}
		
		CGPDFDocumentRef pdf = CGPDFDocumentCreateWithURL((CFURLRef)[NSURL fileURLWithPath:path]);
		size_t pageCount = CGPDFDocumentGetNumberOfPages(pdf);
		
		for (int i = 1; i <= pageCount; i++)
		{
			NSImage *pageImage = renderImageForPageOfPDF(i, pdf, shouldRasterize);
			
			[textSources addObject:renderTextForPageOfPDF(i, pdf)];
			
			NSData *imageData = [pageImage TIFFRepresentation];
			NSBitmapImageRep *imageRep = [NSBitmapImageRep imageRepWithData:imageData];
			NSNumber *compressionFactor = [NSNumber numberWithFloat:0.3];
			NSDictionary *imageProps = [NSDictionary dictionaryWithObject:compressionFactor
																   forKey:NSImageCompressionFactor];
			imageData = [imageRep representationUsingType:NSJPEGFileType properties:imageProps];
			
			[imageData writeToFile:[[oebpsDir stringByAppendingPathComponent:@"Images"] stringByAppendingFormat:@"/%i.jpg", i] atomically:NO];
			
			
			[manifestRoot addChild:[NSXMLNode elementWithName:@"item" children:nil attributes:@[
																								[NSXMLNode attributeWithName:@"id" stringValue:[NSString stringWithFormat:@"j%i", i]],
																								[NSXMLNode attributeWithName:@"href" stringValue:[NSString stringWithFormat:@"Images/%i.jpg", i]],
																								[NSXMLNode attributeWithName:@"media-type" stringValue:@"image/jpeg"]
																								]]];
			
			
			
			if (i == 1)
			{
				[manifestRoot addChild:[NSXMLNode elementWithName:@"item" children:nil attributes:@[
																									[NSXMLNode attributeWithName:@"id" stringValue:@"idcover"],
																									[NSXMLNode attributeWithName:@"href" stringValue:[NSString stringWithFormat:@"Images/%i.jpg", i]],
																									[NSXMLNode attributeWithName:@"media-type" stringValue:@"image/jpeg"],
																									[NSXMLNode attributeWithName:@"properties" stringValue:@"cover-image"]
																									
																									]]];
			}
			
			
			
		}
		
		/* Text */
		
		didCreate = [[NSFileManager defaultManager] createDirectoryAtPath:[oebpsDir stringByAppendingPathComponent:@"Text"] withIntermediateDirectories:YES attributes:nil error:&error];
		
		if (error || !didCreate)
		{
			NSLog(@"%@", error.localizedDescription);
			return -1;
		}
		
		for (int i = 1; i <= pageCount; i++)
		{
			
			NSString *pageSource = @"<?xml version=\"1.0\" encoding=\"utf-8\"?>\
			<!DOCTYPE html>\
			\
			<html xmlns=\"http://www.w3.org/1999/xhtml\" xmlns:xml=\"http://www.w3.org/XML/1998/namespace\" xmlns:epub=\"http://www.idpf.org/2007/ops\" xml:lang=\"en\">\
			<head>\
			<title>%@</title>\
			<meta name=\"viewport\" content=\"width=%i, height=%i\"/>\
			</head>\
			<body style=\"margin: 0px; padding: 0px; border-width:0;\">\
			<img src=\"../Images/%i.jpg\" style=\"position: absolute; left: 0px; top: 0px; select: none;\" />\
			%@\
			</body>\
			</html>";
			
			
			NSString *textSource = nil;
			
			if (!shouldRasterize)
				textSource = textSources[i-1];
			
			CGSize pageSize = documentSize;
			
			NSString *populatedPageSource = [NSString stringWithFormat:pageSource, bookTitle, (int)pageSize.width, (int)pageSize.height, i, textSource];
			
			[populatedPageSource writeToFile:[[oebpsDir stringByAppendingPathComponent:@"Text"] stringByAppendingFormat:@"/p%i.xhtml", i] atomically:NO encoding:NSUTF8StringEncoding error:&error];
			
			[manifestRoot addChild:[NSXMLNode elementWithName:@"item" children:nil attributes:@[
																								[NSXMLNode attributeWithName:@"id" stringValue:[NSString stringWithFormat:@"p%i", i]],
																								[NSXMLNode attributeWithName:@"href" stringValue:[NSString stringWithFormat:@"Text/p%i.xhtml", i]],
																								[NSXMLNode attributeWithName:@"media-type" stringValue:@"application/xhtml+xml"]
																								
																								]]];
			
			[spineRoot addChild:[NSXMLNode elementWithName:@"itemref" children:nil attributes:@[
																								[NSXMLNode attributeWithName:@"idref" stringValue:[NSString stringWithFormat:@"p%i", i]]
																								]]];
		}
		
		
		
		
		/* META-INF */
		
		NSString *metaDir = [tmpDir stringByAppendingPathComponent:@"META-INF"];
		didCreate = [[NSFileManager defaultManager] createDirectoryAtPath:metaDir withIntermediateDirectories:YES attributes:nil error:&error];
		
		if (error || !didCreate)
		{
			NSLog(@"%@", error.localizedDescription);
			return -1;
		}
		
		NSString *metaSrc = @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\
		<container version=\"1.0\" xmlns=\"urn:oasis:names:tc:opendocument:xmlns:container\">\
		<rootfiles>\
		<rootfile full-path=\"OEBPS/content.opf\" media-type=\"application/oebps-package+xml\"/>\
		</rootfiles>\
		</container>";
		
		[metaSrc writeToFile:[metaDir stringByAppendingPathComponent:@"container.xml"] atomically:NO encoding:NSUTF8StringEncoding error:&error];
		
		if (error)
		{
			NSLog(@"%@", error.localizedDescription);
			return -1;
		}
		
		/* TOC */
		
		NSString *tocSrc = @"<?xml version=\"1.0\" encoding=\"utf-8\" ?>\
		<!DOCTYPE ncx PUBLIC \"-//NISO//DTD ncx 2005-1//EN\"\
		\"http://www.daisy.org/z3986/2005/ncx-2005-1.dtd\"><ncx version=\"2005-1\" xmlns=\"http://www.daisy.org/z3986/2005/ncx/\">\
		<head>\
		<meta content=\"ID_UNKNOWN\" name=\"dtb:uid\"/>\
		<meta content=\"0\" name=\"dtb:depth\"/>\
		<meta content=\"%i\" name=\"dtb:totalPageCount\"/>\
		<meta content=\"%i\" name=\"dtb:maxPageNumber\"/>\
		</head>\
		<docTitle>\
		<text>%@</text>\
		</docTitle>\
		<navMap>\
		<navPoint id=\"navPoint-1\" playOrder=\"1\">\
		<navLabel>\
		<text>Start</text>\
		</navLabel>\
		<content src=\"Text/p1.xhtml\"/>\
		</navPoint>\
		</navMap>\
		</ncx>";
		
		tocSrc = [NSString stringWithFormat:tocSrc, pageCount, (pageCount+1), bookTitle];
		
		[tocSrc writeToFile:[oebpsDir stringByAppendingPathComponent:@"toc.ncx"] atomically:NO encoding:NSUTF8StringEncoding error:&error];
		
		[manifestRoot addChild:[NSXMLNode elementWithName:@"item" children:nil attributes:@[
																							[NSXMLNode attributeWithName:@"id" stringValue:@"ncx"],
																							[NSXMLNode attributeWithName:@"href" stringValue:@"toc.ncx"],
																							[NSXMLNode attributeWithName:@"media-type" stringValue:@"application/x-dtbncx+xml"]
																							
																							]]];
		
		if (error)
		{
			NSLog(@"%@", error.localizedDescription);
			return -1;
		}
		
		/* Manifest */
		
		NSData *xmlData = [xmlDoc XMLDataWithOptions:NSXMLNodePrettyPrint];
		if (![xmlData writeToFile:[oebpsDir stringByAppendingPathComponent:@"content.opf"] atomically:YES]) {
			NSLog(@"Could not write content.opf");
			return NO;
		}
		
		/* mimetype */
		
		[@"application/epub+zip" writeToFile:[tmpDir stringByAppendingPathComponent:@"mimetype"] atomically:NO encoding:NSUTF8StringEncoding error:&error];
		
		/* ZIP & Package */
		
		NSTask *zipTask = [[NSTask alloc] init];
		zipTask.launchPath = @"/usr/bin/zip";
		zipTask.arguments = @[@"-r", [bookTitle stringByAppendingPathExtension:@"epub"], @"mimetype", @"META-INF", @"OEBPS"];
		zipTask.currentDirectoryPath = tmpDir;
		
		[zipTask launch];
		
		/* Show results */
		
		[[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:tmpDir]];
	}
	return 0;
}
